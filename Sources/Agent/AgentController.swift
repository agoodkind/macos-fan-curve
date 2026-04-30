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
    private enum ActivityState {
        case inactive
        case active
        case unknown
    }

    private let xpcClient = XPCClient(clientName: generatedAgentBundleID)
    private let sharedConfig = SharedConfig()
    private let loadSampler = CPULoadSampler()
    private let eventWriter = EventArtifactWriter()
    private let tickCoordinator = TickCoordinator()
    private var timer: Timer?
    private var cachedFanCount: UInt = 2
    private var lastActivityState: ActivityState = .unknown
    private var filteredTemperatureFast: Double?
    private var filteredTemperatureSlow: Double?
    private var previousFastTemperature: Double?
    private var previousSlowTemperature: Double?
    private var lastAppliedRPMByFan: [UInt: Float] = [:]
    private var lastPublishedSnapshot: AgentSnapshot?
    private var rawCurvePercentEMA: Double?
    private var controllerMode: AgentControllerMode = .holding
    private var thermalDebt: Double = 0
    private var lastCommandLogPercentByFan: [UInt: Double] = [:]

    private let pollInterval: TimeInterval = 1.0
    private let fastTemperatureEMAAlpha: Double = 0.16
    private let slowTemperatureEMAAlpha: Double = 0.045
    private let rawCurvePercentRiseAlpha: Double = 0.16
    private let rawCurvePercentFallAlpha: Double = 0.015
    private let runtimeBandSize: Double = 0.06
    private let maxRPMRisePerTick: Float = 120
    private let maxRPMFallPerTick: Float = 45
    private let emergencyRampTemperatureC: Double = 92.0
    private let emergencyMaxRPMRisePerTick: Float = 520
    private let thermalDebtRiseRatePerTick: Double = 0.012
    private let thermalDebtFallRatePerTick: Double = 0.012
    private let thermalDebtMinRPMFallPerTick: Float = 15
    private let thermalLeadSeconds: Double = 5.0
    private let maximumThermalLeadC: Double = 4.0
    private let minimumCommandPercentDelta: Double = 0.006
    private let minimumCommandRPMDelta: Float = 35

    private let tempKeys: [String] = SensorCatalog.keysForCurrentHardware()
        .filter { $0.type == .temperature }
        .map(\.key)

    private let cpuTempKeys: Set<String> = Set(
        SensorCatalog.keysForCurrentHardware()
            .filter { $0.type == .temperature && $0.group == .cpu }
            .map(\.key)
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
        _ = await xpcClient.readAndApply(
            fanCount: cachedFanCount,
            tempKeys: [],
            autoFans: Array(0..<cachedFanCount)
        )
        log.notice("agent.fans.reset.auto")
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

            let result = await xpcClient.readAndApply(
                fanCount: cachedFanCount,
                tempKeys: tempKeys
            )
            cachedFanCount = UInt(result.fans.count)

            sharedConfig.writeAgentStatus(pid: ProcessInfo.processInfo.processIdentifier, lastTick: Date())
            sharedConfig.writeAgentLastError(nil)

            let activityState: ActivityState = active ? .active : .inactive
            let transitioned = lastActivityState != activityState
            lastActivityState = activityState
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
                lastCommandLogPercentByFan.removeAll()
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
                    _ = await xpcClient.readAndApply(
                        fanCount: 0,
                        tempKeys: [],
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
                lastAppliedRPMByFan.removeAll()
                rawCurvePercentEMA = nil
                lastCommandLogPercentByFan.removeAll()
                controllerMode = .emergency
                thermalDebt = 0
            } else {
                let points = sharedConfig.loadCurve()
                let mode = sharedConfig.loadInterpolationMode()
                let pressureTemperature = thermalPressureTemperature(
                    rawTemperatureC: maxCPUTemp,
                    fastTemperatureC: fastTemp,
                    slowTemperatureC: slowTemp)
                curvePercent = CurveInterpolation.evaluate(at: pressureTemperature, points: points, mode: mode)
            }

            var assistAppliedKinds: [LoadAssistKind] = []
            var assistFloorPercent: Double?
            var rawBaselinePercent = curvePercent
            if !boost {
                for kind in LoadAssistKind.allCases where sharedConfig.loadLoadAssistEnabled(kind) {
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
                    assistFloorPercent: assistFloorPercent
                )
            }

            let assistSummary = assistAppliedKinds.map(\.rawValue).joined(separator: ",")
            log.debug(
                "agent.tick cpuTemp=\(Int(maxCPUTemp), privacy: .public)C cpuLoad=\(Int(cpuLoad), privacy: .public)% gpuLoad=\(Int(gpuLoad), privacy: .public)% raw=\(Int(runtimeState.rawBaselinePercent * 100), privacy: .public)% committed=\(Int(runtimeState.committedPercent * 100), privacy: .public)% mode=\(runtimeState.mode.rawValue, privacy: .public) debt=\(Int(thermalDebt * 100), privacy: .public)% boost=\(boost, privacy: .public) assist=\(assistSummary, privacy: .public)"
            )

            var setFans: [(index: UInt, rpm: Float)] = []
            var autoFans: [UInt] = []
            for (fanIndex, fan) in result.fans.enumerated() {
                let command = fanCommandFor(
                    percent: runtimeState.committedPercent, minRPM: fan.minRPM, maxRPM: fan.maxRPM)
                let smoothedCommand =
                    boost
                    ? command
                    : slewLimitedCommand(
                        command,
                        for: UInt(fanIndex),
                        currentFan: fan,
                        currentTemperatureC: maxCPUTemp)
                switch command {
                case .setRPM:
                    if case .setRPM(let rpm) = smoothedCommand {
                        setFans.append((index: UInt(fanIndex), rpm: rpm))
                    }
                case .auto:
                    lastAppliedRPMByFan.removeValue(forKey: UInt(fanIndex))
                    autoFans.append(UInt(fanIndex))
                }
            }

            let tickPriority =
                boost
                ? sharedConfig.loadUserBoostPriority()
                : sharedConfig.loadCurveNormalPriority()

            _ = await xpcClient.readAndApply(
                fanCount: 0,
                tempKeys: [],
                setFans: setFans,
                autoFans: autoFans,
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
                EventArtifactWriter.AppendRequest(
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
                    fanActualRPM: result.fans.map(\.actualRPM),
                    fanTargetRPM: result.fans.map(\.targetRPM),
                    fanMinRPM: result.fans.map(\.minRPM),
                    fanMaxRPM: result.fans.map(\.maxRPM),
                    fanManualMode: result.fans.map(\.manualMode)))
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
        assistFloorPercent: Double?
    ) -> RuntimeBandState {
        let fastTrend = previousFastTemperature.map { fastTemperatureC - $0 } ?? 0
        let slowTrend = previousSlowTemperature.map { slowTemperatureC - $0 } ?? 0
        let pressureTemperature = thermalPressureTemperature(
            rawTemperatureC: rawTemperatureC,
            fastTemperatureC: fastTemperatureC,
            slowTemperatureC: slowTemperatureC)

        let baselinePercent = max(0, min(1, rawBaselinePercent))
        let targetPercent = max(baselinePercent, assistFloorPercent ?? 0)
        let previousCommittedPercent = rawCurvePercentEMA ?? targetPercent
        let emergency = rawTemperatureC >= emergencyRampTemperatureC

        let maxCurveOvershoot = emergency ? 1.0 : (slowTemperatureC >= 85 ? 0.12 : 0.08)
        let maxAllowedPercent = min(1.0, targetPercent + maxCurveOvershoot)
        let minAllowedPercent = max(assistFloorPercent ?? 0, targetPercent - 0.02)

        let targetDelta = targetPercent - previousCommittedPercent
        let nextCommittedPercent: Double
        if emergency {
            nextCommittedPercent = max(previousCommittedPercent, targetPercent)
            controllerMode = .emergency
        } else if abs(targetDelta) < 0.006 {
            nextCommittedPercent = max(minAllowedPercent, min(maxAllowedPercent, previousCommittedPercent))
            controllerMode = .holding
        } else if targetDelta > 0 {
            let riseStep = max(0.006, min(0.03, targetDelta * rawCurvePercentRiseAlpha))
            nextCommittedPercent = min(maxAllowedPercent, previousCommittedPercent + riseStep)
            controllerMode = .rampingUp
        } else {
            let aboveCurveBy = previousCommittedPercent - targetPercent
            if aboveCurveBy > maxCurveOvershoot {
                nextCommittedPercent = max(maxAllowedPercent, previousCommittedPercent - 0.035)
            } else {
                let fallStep = max(0.0012, min(0.006, abs(targetDelta) * rawCurvePercentFallAlpha))
                nextCommittedPercent = max(minAllowedPercent, previousCommittedPercent - fallStep)
            }
            controllerMode = .rampingDown
        }

        let committedPercent = max(0, min(1, nextCommittedPercent))
        rawCurvePercentEMA = committedPercent
        let nextBandIndex = bandIndex(for: committedPercent)

        updateThermalDebt(
            rawTemperatureC: rawTemperatureC,
            fastTemperatureC: fastTemperatureC,
            slowTemperatureC: slowTemperatureC,
            fastTrend: fastTrend,
            slowTrend: slowTrend,
            cpuLoad: cpuLoad,
            rawBaselinePercent: rawBaselinePercent,
            committedPercent: committedPercent,
            steppedUp: committedPercent > previousCommittedPercent
        )
        return RuntimeBandState(
            committedPercent: max(committedPercent, assistFloorPercent ?? 0),
            bandIndex: nextBandIndex,
            committedTemperatureC: slowTemperatureC,
            rawBaselinePercent: rawBaselinePercent,
            rawPressureTemperatureC: pressureTemperature,
            mode: controllerMode,
            holdRemainingSeconds: 0
        )
    }

    private func bandIndex(for percent: Double) -> Int {
        let clamped = max(0, min(1, percent))
        guard clamped > 0 else { return 0 }
        let bands = Int((1.0 / runtimeBandSize).rounded())
        return min(bands, Int(ceil(clamped / runtimeBandSize)))
    }

    private func thermalPressureTemperature(
        rawTemperatureC: Double,
        fastTemperatureC: Double,
        slowTemperatureC: Double
    ) -> Double {
        let fastTrend = previousFastTemperature.map { fastTemperatureC - $0 } ?? 0
        let trendLead = max(0, min(maximumThermalLeadC, fastTrend * thermalLeadSeconds))
        let ledTemperature = fastTemperatureC + trendLead
        return max(rawTemperatureC, slowTemperatureC, ledTemperature)
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
            let baseline =
                commandBaselineRPM(
                    fanIndex: index,
                    requestedRPM: requestedRPM,
                    currentFan: currentFan)
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
            let next = snappedCommandRPM(
                requestedRPM: requestedRPM,
                candidateRPM: max(0, baseline + limitedDelta),
                delta: delta)
            lastAppliedRPMByFan[index] = next
            logCommandChangeIfNeeded(
                fanIndex: index,
                requestedRPM: requestedRPM,
                commandedRPM: next,
                currentFan: currentFan,
                currentTemperatureC: currentTemperatureC)
            return .setRPM(next)
        }
    }

    private func commandBaselineRPM(
        fanIndex: UInt,
        requestedRPM: Float,
        currentFan: FanInfo
    ) -> Float {
        if let previous = lastAppliedRPMByFan[fanIndex] {
            return previous
        }

        let observedRPM = currentFan.actualRPM > 0 ? currentFan.actualRPM : currentFan.targetRPM
        guard currentFan.targetRPM > 0 else { return observedRPM }
        if requestedRPM < currentFan.targetRPM {
            return min(currentFan.targetRPM, observedRPM)
        }
        return max(currentFan.targetRPM, observedRPM)
    }

    private func snappedCommandRPM(
        requestedRPM: Float,
        candidateRPM: Float,
        delta: Float
    ) -> Float {
        guard abs(delta) > minimumCommandRPMDelta else {
            return requestedRPM
        }
        if delta > 0 {
            return min(requestedRPM, candidateRPM)
        }
        return max(requestedRPM, candidateRPM)
    }

    private func logCommandChangeIfNeeded(
        fanIndex: UInt,
        requestedRPM: Float,
        commandedRPM: Float,
        currentFan: FanInfo,
        currentTemperatureC: Double
    ) {
        guard currentFan.maxRPM > currentFan.minRPM else { return }
        let commandedPercent = Double((commandedRPM - currentFan.minRPM) / (currentFan.maxRPM - currentFan.minRPM))
        let previousPercent = lastCommandLogPercentByFan[fanIndex]
        guard previousPercent == nil || abs((previousPercent ?? 0) - commandedPercent) >= minimumCommandPercentDelta else {
            return
        }
        lastCommandLogPercentByFan[fanIndex] = commandedPercent
        log.info(
            "agent.fan.command fan=\(fanIndex, privacy: .public) requestedRPM=\(Int(requestedRPM), privacy: .public) commandedRPM=\(Int(commandedRPM), privacy: .public) actualRPM=\(Int(currentFan.actualRPM), privacy: .public) tempC=\(Int(currentTemperatureC), privacy: .public) mode=\(controllerMode.rawValue, privacy: .public)"
        )
    }
}
