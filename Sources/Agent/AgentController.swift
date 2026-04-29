//
//  AgentController.swift
//  FanCurveAgent
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import AppLog
import Foundation
import SMCFanKit

private let log = AppLog.make(category: "AgentController")

private actor TickCoordinator {
    private var tickInFlight = false
    private var tickPending = false

    func requestTick() -> Bool {
        if tickInFlight {
            tickPending = true
            return false
        }
        tickInFlight = true
        return true
    }

    func finishTick() -> Bool {
        if tickPending {
            tickPending = false
            return true
        }
        tickInFlight = false
        return false
    }
}

/// Runs the curve application loop in the background agent process.
/// Reads curve config from the shared UserDefaults suite every tick and
/// applies it via the privileged helper over XPC.
final class AgentController: @unchecked Sendable {
    private let xpcClient = XPCClient(clientName: generatedAgentBundleID)
    private let sharedConfig = SharedConfig()
    private let loadSampler = CPULoadSampler()
    private let eventWriter = EventArtifactWriter()
    private let tickCoordinator = TickCoordinator()
    private var timer: Timer?
    private var cachedFanCount: UInt = 2
    private var lastActive: Bool? = nil
    private var filteredTemperatureFast: Double? = nil
    private var filteredTemperatureSlow: Double? = nil
    private var previousFastTemperature: Double? = nil
    private var previousSlowTemperature: Double? = nil
    private var lastAppliedRPMByFan: [UInt: Float] = [:]
    private var lastPublishedSnapshot: AgentSnapshot? = nil
    private var committedBandIndex: Int? = nil
    private var bandEnteredAt: Date? = nil
    private var bandHoldUntil: Date? = nil
    private var lastBandChangeAt: Date? = nil
    private var upPressureScore: Double = 0
    private var downPressureScore: Double = 0
    private var rawCurvePercentEMA: Double? = nil
    private var controllerMode: AgentControllerMode = .holding
    private var thermalDebt: Double = 0

    private let pollInterval: TimeInterval = 1.0
    private let fastTemperatureEMAAlpha: Double = 0.08
    private let slowTemperatureEMAAlpha: Double = 0.025
    private let rawCurvePercentEMAAlpha: Double = 0.035
    private let runtimeBandSize: Double = 0.06
    private let bandMinimumDwell: TimeInterval = 300.0
    private let reboundHoldExtension: TimeInterval = 180.0
    private let minimumBandTransitionInterval: TimeInterval = 60.0
    private let maxRPMRisePerTick: Float = 18
    private let maxRPMFallPerTick: Float = 4
    private let emergencyRampTemperatureC: Double = 92.0
    private let emergencyBandEscapeTemperatureC: Double = 96.0
    private let emergencyMaxRPMRisePerTick: Float = 220
    private let positiveFastTrendThresholdCPerTick: Double = 0.40
    private let coolingTrendThresholdCPerTick: Double = -0.06
    private let reboundTemperatureBandC: Double = 0.30
    private let upPressureStepThreshold: Double = 18.0
    private let downPressureStepThreshold: Double = 150.0
    private let downPressureDecayOnRebound: Double = 0.08
    private let maxCurveOvershootBands: Int = 2
    private let fastCatchupGapBands: Int = 5
    private let fidelityCatchupDwell: TimeInterval = 90.0
    private let thermalDebtRiseRatePerTick: Double = 0.035
    private let thermalDebtFallRatePerTick: Double = 0.0015
    private let thermalDebtMaxHoldExtension: TimeInterval = 300.0
    private let thermalDebtMaxDownThresholdBonus: Double = 120.0
    private let thermalDebtMinRPMFallPerTick: Float = 1.0

    private let tempKeys: [String] = SensorCatalog.keysForCurrentHardware()
        .filter { $0.type == .temperature }
        .map { $0.key }

    private let cpuTempKeys: Set<String> = Set(
        SensorCatalog.keysForCurrentHardware()
            .filter { $0.type == .temperature && $0.group == .cpu }
            .map { $0.key }
    )

    func start() {
        log.notice("agent.started pollInterval=\(pollInterval, privacy: .public)s")
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.requestTick()
        }
        registerDarwinObserver()
        requestTick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        unregisterDarwinObserver()
        sharedConfig.clearAgentStatus()
        xpcClient.shutdown()
        log.notice("agent.stopped")
    }

    private func registerDarwinObserver() {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let controller = Unmanaged<AgentController>
                    .fromOpaque(observer).takeUnretainedValue()
                controller.requestTick()
            },
            SharedConfigPush.notificationName,
            nil,
            .deliverImmediately)
        log.info("agent.darwin.observer.registered name=\(SharedConfigPush.notificationNameString, privacy: .public)")
    }

    private func unregisterDarwinObserver() {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer)
    }

    /// Reset all fans to auto mode. Called on SIGTERM/SIGINT before exit.
    func resetAllFansToAuto() async {
        do {
            _ = try await xpcClient.readAndApply(
                fanCount: cachedFanCount,
                tempKeys: [],
                setFans: nil,
                autoFans: Array(0..<cachedFanCount)
            )
            log.notice("agent.fans.reset.auto")
        } catch {
            log.error("agent.fans.reset.failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func requestTick() {
        Task { [weak self] in
            guard let self else { return }
            guard await tickCoordinator.requestTick() else { return }
            await runTickLoop()
        }
    }

    private func runTickLoop() async {
        while true {
            await tick()

            if await tickCoordinator.finishTick() {
                continue
            }
            return
        }
    }

    private func tick() async {
        let active = sharedConfig.loadIsActive()

        do {
            let result = try await xpcClient.readAndApply(
                fanCount: cachedFanCount,
                tempKeys: tempKeys,
                setFans: nil,
                autoFans: nil
            )
            cachedFanCount = UInt(result.fans.count)

            sharedConfig.writeAgentStatus(pid: ProcessInfo.processInfo.processIdentifier, lastTick: Date())
            sharedConfig.writeAgentLastError(nil)

            let transitioned = (lastActive != active)
            lastActive = active
            var maxCPUTemp: Double = 0
            for (key, value) in result.temps where cpuTempKeys.contains(key) {
                maxCPUTemp = max(maxCPUTemp, Double(value))
            }
            loadSampler.sample()
            let cpuLoad = loadSampler.smoothed
            let gpuLoad = readGPULoadPercent()
            if !active {
                filteredTemperatureFast = nil
                filteredTemperatureSlow = nil
                previousFastTemperature = nil
                previousSlowTemperature = nil
                lastAppliedRPMByFan.removeAll()
                committedBandIndex = nil
                bandEnteredAt = nil
                bandHoldUntil = nil
                lastBandChangeAt = nil
                upPressureScore = 0
                downPressureScore = 0
                rawCurvePercentEMA = nil
                controllerMode = .holding
                thermalDebt = 0
                publishSnapshotIfNeeded(
                    AgentSnapshot(
                        timestamp: Date(),
                        helperReachable: true,
                        curveActive: false,
                        boostEnabled: false,
                        governingTemperatureC: maxCPUTemp,
                        committedTemperatureC: maxCPUTemp,
                        rawPressureTemperatureC: maxCPUTemp > 0 ? maxCPUTemp : nil,
                        cpuLoadPercent: cpuLoad,
                        gpuLoadPercent: gpuLoad,
                        effectiveCurvePercent: 0,
                        rawBaselinePercent: 0,
                        committedPercent: 0,
                        controllerMode: .holding,
                        bandIndex: 0,
                        holdRemainingSeconds: 0,
                        assistFloorPercent: nil,
                        activeAssistKinds: [],
                        fans: result.fans.enumerated().map { index, fan in
                            AgentFanSnapshot(
                                index: index,
                                actualRPM: fan.actualRPM,
                                targetRPM: fan.targetRPM,
                                minRPM: fan.minRPM,
                                maxRPM: fan.maxRPM,
                                manualMode: fan.manualMode)
                        }))
                if transitioned, !result.fans.isEmpty {
                    _ = try? await xpcClient.readAndApply(
                        fanCount: 0,
                        tempKeys: [],
                        setFans: nil,
                        autoFans: Array(0..<UInt(result.fans.count))
                    )
                    log.notice("agent.curve.deactivated fans=auto")
                }
                return
            }
            guard !result.fans.isEmpty else { return }

            guard maxCPUTemp > 0 else { return }
            let now = Date()
            let fastTemp = smoothedTemperature(
                rawTemp: maxCPUTemp,
                current: filteredTemperatureFast,
                previous: &previousFastTemperature,
                alpha: fastTemperatureEMAAlpha)
            filteredTemperatureFast = fastTemp
            let slowTemp = smoothedTemperature(
                rawTemp: maxCPUTemp,
                current: filteredTemperatureSlow,
                previous: &previousSlowTemperature,
                alpha: slowTemperatureEMAAlpha)
            filteredTemperatureSlow = slowTemp

            let boost = sharedConfig.loadBoostEnabled()
            let curvePercent: Double
            if boost {
                curvePercent = 1.0
                filteredTemperatureFast = nil
                filteredTemperatureSlow = nil
                previousFastTemperature = nil
                previousSlowTemperature = nil
                committedBandIndex = nil
                bandEnteredAt = nil
                bandHoldUntil = nil
                lastBandChangeAt = nil
                upPressureScore = 0
                downPressureScore = 0
                rawCurvePercentEMA = nil
                controllerMode = .emergency
                thermalDebt = 0
            } else {
                let points = sharedConfig.loadCurve()
                let mode = sharedConfig.loadInterpolationMode()
                curvePercent = CurveInterpolation.evaluate(at: fastTemp, points: points, mode: mode)
            }

            var assistAppliedKinds: [LoadAssistKind] = []
            var assistFloorPercent: Double? = nil
            var rawBaselinePercent = curvePercent
            if !boost {
                for kind in LoadAssistKind.allCases {
                    guard sharedConfig.loadLoadAssistEnabled(kind) else { continue }
                    let loadPercent = kind == .cpu ? cpuLoad : gpuLoad
                    let assistFloor = CurveInterpolation.evaluate(
                        at: loadPercent,
                        points: sharedConfig.loadLoadAssistCurve(kind),
                        mode: .linear)
                    if assistFloor > rawBaselinePercent {
                        rawBaselinePercent = assistFloor
                        assistFloorPercent = assistFloor
                        assistAppliedKinds = [kind]
                    } else if assistFloor == rawBaselinePercent, assistFloor > 0 {
                        assistFloorPercent = assistFloor
                        assistAppliedKinds.append(kind)
                    }
                }
            }

            let runtimeState: RuntimeBandState
            if boost {
                runtimeState = RuntimeBandState(
                    committedPercent: 1.0,
                    bandIndex: bandIndex(for: 1.0),
                    committedTemperatureC: maxCPUTemp,
                    rawBaselinePercent: 1.0,
                    rawPressureTemperatureC: maxCPUTemp,
                    mode: .emergency,
                    holdRemainingSeconds: 0
                )
            } else {
                runtimeState = bandControlledState(
                    rawBaselinePercent: rawBaselinePercent,
                    rawTemperatureC: maxCPUTemp,
                    fastTemperatureC: fastTemp,
                    slowTemperatureC: slowTemp,
                    cpuLoad: cpuLoad,
                    assistFloorPercent: assistFloorPercent,
                    now: now
                )
            }

            let assistSummary = assistAppliedKinds.map(\.rawValue).joined(separator: ",")
            log.debug("agent.tick cpuTemp=\(Int(maxCPUTemp), privacy: .public)C cpuLoad=\(Int(cpuLoad), privacy: .public)% gpuLoad=\(Int(gpuLoad), privacy: .public)% raw=\(Int(runtimeState.rawBaselinePercent * 100), privacy: .public)% committed=\(Int(runtimeState.committedPercent * 100), privacy: .public)% mode=\(runtimeState.mode.rawValue, privacy: .public) debt=\(Int(thermalDebt * 100), privacy: .public)% boost=\(boost, privacy: .public) assist=\(assistSummary, privacy: .public)")

            var setFans: [(index: UInt, rpm: Float)] = []
            var autoFans: [UInt] = []
            for (i, fan) in result.fans.enumerated() {
                let command = fanCommandFor(percent: runtimeState.committedPercent, minRPM: fan.minRPM, maxRPM: fan.maxRPM)
                let smoothedCommand = boost
                    ? command
                    : slewLimitedCommand(
                        command,
                        for: UInt(i),
                        currentFan: fan,
                        currentTemperatureC: maxCPUTemp)
                switch command {
                case .setRPM:
                    if case .setRPM(let rpm) = smoothedCommand {
                        setFans.append((index: UInt(i), rpm: rpm))
                    }
                case .auto:
                    lastAppliedRPMByFan.removeValue(forKey: UInt(i))
                    autoFans.append(UInt(i))
                }
            }

            let tickPriority = boost
                ? sharedConfig.loadUserBoostPriority()
                : sharedConfig.loadCurveNormalPriority()

            _ = try await xpcClient.readAndApply(
                fanCount: 0,
                tempKeys: [],
                setFans: setFans.isEmpty ? nil : setFans,
                autoFans: autoFans.isEmpty ? nil : autoFans,
                priority: tickPriority
            )

            publishSnapshotIfNeeded(
                AgentSnapshot(
                    timestamp: now,
                    helperReachable: true,
                    curveActive: active,
                    boostEnabled: boost,
                    governingTemperatureC: maxCPUTemp,
                    committedTemperatureC: runtimeState.committedTemperatureC,
                    rawPressureTemperatureC: runtimeState.rawPressureTemperatureC,
                    cpuLoadPercent: cpuLoad,
                    gpuLoadPercent: gpuLoad,
                    effectiveCurvePercent: runtimeState.committedPercent,
                    rawBaselinePercent: runtimeState.rawBaselinePercent,
                    committedPercent: runtimeState.committedPercent,
                    controllerMode: runtimeState.mode,
                    bandIndex: runtimeState.bandIndex,
                    holdRemainingSeconds: runtimeState.holdRemainingSeconds,
                    assistFloorPercent: assistFloorPercent,
                    activeAssistKinds: assistAppliedKinds,
                    fans: result.fans.enumerated().map { index, fan in
                        AgentFanSnapshot(
                            index: index,
                            actualRPM: fan.actualRPM,
                            targetRPM: fan.targetRPM,
                            minRPM: fan.minRPM,
                            maxRPM: fan.maxRPM,
                            manualMode: fan.manualMode)
                    }))

            eventWriter.append(
                timestamp: now,
                kind: boost ? "boost" : (assistAppliedKinds.isEmpty ? "curve" : "assist:\(assistSummary)"),
                governingTempC: maxCPUTemp,
                rawTemperatureC: maxCPUTemp,
                fastTemperatureC: fastTemp,
                slowTemperatureC: slowTemp,
                cpuLoadPercent: cpuLoad,
                gpuLoadPercent: gpuLoad,
                effectiveCurvePercent: runtimeState.committedPercent,
                rawBaselinePercent: runtimeState.rawBaselinePercent,
                committedPercent: runtimeState.committedPercent,
                bandIndex: runtimeState.bandIndex,
                holdRemainingSeconds: runtimeState.holdRemainingSeconds,
                thermalDebt: thermalDebt,
                controllerMode: runtimeState.mode.rawValue,
                assistFloorPercent: assistFloorPercent,
                activeAssistKinds: assistAppliedKinds.map(\.rawValue),
                fanActualRPM: result.fans.map { $0.actualRPM },
                fanTargetRPM: result.fans.map { $0.targetRPM },
                fanMinRPM: result.fans.map { $0.minRPM },
                fanMaxRPM: result.fans.map { $0.maxRPM },
                fanManualMode: result.fans.map { $0.manualMode })
        } catch {
            log.error("agent.tick.failed error=\(error.localizedDescription, privacy: .public)")
            sharedConfig.writeAgentLastError("\(error)")
        }
    }

    private func publishSnapshotIfNeeded(_ snapshot: AgentSnapshot) {
        sharedConfig.writeAgentSnapshot(snapshot)
        if lastPublishedSnapshot != snapshot {
            lastPublishedSnapshot = snapshot
            AgentSnapshotPush.post()
        }
    }

    private func smoothedTemperature(
        rawTemp: Double,
        current: Double?,
        previous: inout Double?,
        alpha: Double
    ) -> Double {
        guard let current else {
            previous = nil
            return rawTemp
        }

        previous = current
        return alpha * rawTemp + (1.0 - alpha) * current
    }

    private struct RuntimeBandState {
        let committedPercent: Double
        let bandIndex: Int
        let committedTemperatureC: Double
        let rawBaselinePercent: Double
        let rawPressureTemperatureC: Double?
        let mode: AgentControllerMode
        let holdRemainingSeconds: Double
    }

    private func bandControlledState(
        rawBaselinePercent: Double,
        rawTemperatureC: Double,
        fastTemperatureC: Double,
        slowTemperatureC: Double,
        cpuLoad: Double,
        assistFloorPercent: Double?,
        now: Date
    ) -> RuntimeBandState {
        let smoothedBaseline: Double
        if let rawCurvePercentEMA {
            smoothedBaseline = rawCurvePercentEMAAlpha * rawBaselinePercent
                + (1.0 - rawCurvePercentEMAAlpha) * rawCurvePercentEMA
        } else {
            smoothedBaseline = rawBaselinePercent
        }
        rawCurvePercentEMA = smoothedBaseline

        let targetBandIndex = bandIndex(for: max(rawBaselinePercent, smoothedBaseline))
        let assistFloorBandIndex = bandIndex(for: assistFloorPercent ?? 0)
        let effectiveBandMinimumDwell = bandMinimumDwell + thermalDebt * thermalDebtMaxHoldExtension
        let effectiveDownPressureStepThreshold =
            downPressureStepThreshold + thermalDebt * thermalDebtMaxDownThresholdBonus
        let fastTrend = previousFastTemperature.map { fastTemperatureC - $0 } ?? 0
        let slowTrend = previousSlowTemperature.map { slowTemperatureC - $0 } ?? 0
        let thermalGap = rawTemperatureC - slowTemperatureC

        guard let existingBandIndex = committedBandIndex else {
            let initialBandIndex = max(targetBandIndex, assistFloorBandIndex)
            committedBandIndex = initialBandIndex
            bandEnteredAt = now
            bandHoldUntil = now.addingTimeInterval(effectiveBandMinimumDwell)
            lastBandChangeAt = now
            upPressureScore = 0
            downPressureScore = 0
            controllerMode = .holding
            updateThermalDebt(
                rawTemperatureC: rawTemperatureC,
                fastTemperatureC: fastTemperatureC,
                slowTemperatureC: slowTemperatureC,
                fastTrend: fastTrend,
                slowTrend: slowTrend,
                cpuLoad: cpuLoad,
                rawBaselinePercent: rawBaselinePercent,
                committedPercent: percent(forBand: initialBandIndex),
                steppedUp: false
            )
            let committedPercent = percent(forBand: initialBandIndex)
            return RuntimeBandState(
                committedPercent: committedPercent,
                bandIndex: initialBandIndex,
                committedTemperatureC: slowTemperatureC,
                rawBaselinePercent: rawBaselinePercent,
                rawPressureTemperatureC: fastTemperatureC,
                mode: controllerMode,
                holdRemainingSeconds: max(0, bandHoldUntil?.timeIntervalSince(now) ?? 0)
            )
        }

        var nextBandIndex = max(existingBandIndex, assistFloorBandIndex)
        let rebound = fastTrend > 0.02 || thermalGap >= reboundTemperatureBandC || targetBandIndex >= nextBandIndex
        let emergency = rawTemperatureC >= emergencyBandEscapeTemperatureC
            || (rawTemperatureC >= emergencyRampTemperatureC && targetBandIndex > nextBandIndex + 1)

        if emergency {
            nextBandIndex = max(targetBandIndex, assistFloorBandIndex)
            upPressureScore = 0
            downPressureScore = 0
            controllerMode = .emergency
            committedBandIndex = nextBandIndex
            bandEnteredAt = now
            bandHoldUntil = now.addingTimeInterval(effectiveBandMinimumDwell)
            lastBandChangeAt = now
        } else {
            if targetBandIndex > nextBandIndex {
                let gap = Double(targetBandIndex - nextBandIndex)
                let trendPressure = fastTrend > positiveFastTrendThresholdCPerTick ? 1.0 : max(0, fastTrend * 2.5)
                let thermalPressure = max(0, thermalGap - 0.2) * 0.4
                upPressureScore = min(80.0, upPressureScore + 1.0 + gap * 0.55 + trendPressure + thermalPressure)
                downPressureScore = max(0, downPressureScore - 1.5)
            } else {
                upPressureScore = max(0, upPressureScore - 0.9)
            }

            let stableCooling = fastTrend <= 0.01 && slowTrend <= coolingTrendThresholdCPerTick
            let fidelityGuardActive =
                !rebound
                && thermalDebt < 0.08
                && now >= (bandHoldUntil ?? .distantPast)
                && downPressureScore >= effectiveDownPressureStepThreshold
                && nextBandIndex > targetBandIndex + maxCurveOvershootBands
                && thermalGap <= 0.45
                && fastTrend <= -0.02

            if targetBandIndex < nextBandIndex && !rebound {
                let gap = Double(nextBandIndex - targetBandIndex)
                let coolingPressure = stableCooling ? 1.0 : 0.35
                let curveSlack = max(0, percent(forBand: nextBandIndex) - rawBaselinePercent) * 18.0
                downPressureScore = min(
                    240.0,
                    downPressureScore + coolingPressure + gap * 0.35 + curveSlack
                )
            } else if rebound {
                downPressureScore *= downPressureDecayOnRebound
                bandHoldUntil = max(
                    bandHoldUntil ?? now,
                    now.addingTimeInterval(reboundHoldExtension + thermalDebt * 20.0)
                )
            } else {
                downPressureScore = max(0, downPressureScore - 0.6)
            }

            let transitionReady = now.timeIntervalSince(lastBandChangeAt ?? .distantPast) >= minimumBandTransitionInterval
            if fidelityGuardActive && transitionReady {
                let cappedTargetBandIndex = max(assistFloorBandIndex, targetBandIndex + maxCurveOvershootBands)
                if nextBandIndex - cappedTargetBandIndex >= fastCatchupGapBands {
                    nextBandIndex = cappedTargetBandIndex
                } else {
                    nextBandIndex = max(cappedTargetBandIndex, nextBandIndex - 2)
                }
                upPressureScore = 0
                downPressureScore = 0
                controllerMode = .rampingDown
                committedBandIndex = nextBandIndex
                bandEnteredAt = now
                bandHoldUntil = now.addingTimeInterval(fidelityCatchupDwell)
                lastBandChangeAt = now
            } else if targetBandIndex > nextBandIndex && transitionReady && upPressureScore >= upPressureStepThreshold {
                nextBandIndex += 1
                upPressureScore = 0
                downPressureScore = 0
                controllerMode = .rampingUp
                committedBandIndex = nextBandIndex
                bandEnteredAt = now
                bandHoldUntil = now.addingTimeInterval(effectiveBandMinimumDwell)
                lastBandChangeAt = now
            } else if nextBandIndex > assistFloorBandIndex,
                targetBandIndex < nextBandIndex,
                transitionReady,
                now >= (bandHoldUntil ?? .distantPast),
                downPressureScore >= effectiveDownPressureStepThreshold
            {
                nextBandIndex -= 1
                nextBandIndex = max(nextBandIndex, assistFloorBandIndex)
                upPressureScore = 0
                downPressureScore = 0
                controllerMode = .rampingDown
                committedBandIndex = nextBandIndex
                bandEnteredAt = now
                bandHoldUntil = now.addingTimeInterval(effectiveBandMinimumDwell)
                lastBandChangeAt = now
            } else {
                committedBandIndex = nextBandIndex
                controllerMode = .holding
            }
        }

        let committedPercent = percent(forBand: nextBandIndex)
        updateThermalDebt(
            rawTemperatureC: rawTemperatureC,
            fastTemperatureC: fastTemperatureC,
            slowTemperatureC: slowTemperatureC,
            fastTrend: fastTrend,
            slowTrend: slowTrend,
            cpuLoad: cpuLoad,
            rawBaselinePercent: rawBaselinePercent,
            committedPercent: committedPercent,
            steppedUp: nextBandIndex > existingBandIndex
        )
        return RuntimeBandState(
            committedPercent: max(committedPercent, assistFloorPercent ?? 0),
            bandIndex: nextBandIndex,
            committedTemperatureC: slowTemperatureC,
            rawBaselinePercent: rawBaselinePercent,
            rawPressureTemperatureC: fastTemperatureC,
            mode: controllerMode,
            holdRemainingSeconds: max(0, bandHoldUntil?.timeIntervalSince(now) ?? 0)
        )
    }

    private func bandIndex(for percent: Double) -> Int {
        let clamped = max(0, min(1, percent))
        guard clamped > 0 else { return 0 }
        let bands = Int((1.0 / runtimeBandSize).rounded())
        return min(bands, Int(ceil(clamped / runtimeBandSize)))
    }

    private func percent(forBand index: Int) -> Double {
        max(0, min(1, Double(index) * runtimeBandSize))
    }

    private func updateThermalDebt(
        rawTemperatureC: Double,
        fastTemperatureC: Double,
        slowTemperatureC: Double,
        fastTrend: Double,
        slowTrend: Double,
        cpuLoad: Double,
        rawBaselinePercent: Double,
        committedPercent: Double,
        steppedUp: Bool
    ) {
        let comfortOverTemp = max(0, slowTemperatureC - 58.0) / 22.0
        let risePressure = max(0, fastTemperatureC - slowTemperatureC - 0.25) / 3.0
        let fastTrendPressure = max(0, fastTrend - 0.04) * 2.8
        let sustainedLoadPressure = max(0, cpuLoad - 45.0) / 55.0 * 0.35
        let bandEscalationPressure = steppedUp ? 0.22 : 0.0

        let stableCooling =
            fastTrend <= 0.01
            && slowTrend <= -0.02
            && rawBaselinePercent <= committedPercent + 0.001
        let coolingPressure = stableCooling ? 1.0 : 0.0
        let lowLoadPressure = cpuLoad < 25.0 ? 0.4 : 0.0
        let coolTempPressure = slowTemperatureC < 52.0 && rawTemperatureC < 55.0 ? 0.35 : 0.0

        let heatContribution =
            comfortOverTemp
            + risePressure
            + fastTrendPressure
            + sustainedLoadPressure
            + bandEscalationPressure
        let coolingContribution = coolingPressure + lowLoadPressure + coolTempPressure

        thermalDebt = max(
            0,
            min(
                1,
                thermalDebt
                    + thermalDebtRiseRatePerTick * heatContribution
                    - thermalDebtFallRatePerTick * coolingContribution
            )
        )
    }

    /// Limit how quickly commanded RPM can change between ticks so the
    /// acoustic ramp feels closer to Apple's gradual fan behavior.
    private func slewLimitedCommand(
        _ command: FanCommand,
        for index: UInt,
        currentFan: FanInfo,
        currentTemperatureC: Double
    ) -> FanCommand {
        switch command {
        case .auto:
            lastAppliedRPMByFan.removeValue(forKey: index)
            return .auto
        case .setRPM(let requestedRPM):
            let baseline = lastAppliedRPMByFan[index]
                ?? (currentFan.targetRPM > 0 ? currentFan.targetRPM : currentFan.actualRPM)
            let delta = requestedRPM - baseline
            let limitedDelta: Float
            if delta > 0 {
                let riseLimit =
                    currentTemperatureC >= emergencyRampTemperatureC
                    ? emergencyMaxRPMRisePerTick
                    : maxRPMRisePerTick
                limitedDelta = min(delta, riseLimit)
            } else {
                let effectiveMaxRPMFallPerTick =
                    maxRPMFallPerTick
                    - Float(thermalDebt) * (maxRPMFallPerTick - thermalDebtMinRPMFallPerTick)
                limitedDelta = max(delta, -effectiveMaxRPMFallPerTick)
            }
            let next = max(0, baseline + limitedDelta)
            lastAppliedRPMByFan[index] = next
            return .setRPM(next)
        }
    }
}
