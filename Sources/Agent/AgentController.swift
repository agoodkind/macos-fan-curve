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
    private var rampStateByFan: [UInt: RampCommandState] = [:]
    private var lastPublishedSnapshot: AgentSnapshot?
    private var controllerMode: AgentControllerMode = .holding
    private var thermalDebt: Double = 0
    private var lastCommandLogPercentByFan: [UInt: Double] = [:]
    private var conditionedDemandPercent: Double?
    private var conditionedDemandPercentVelocity: Double = 0
    private var conditionedDemandTemperatureC: Double?
    private var conditionedDemandTemperatureVelocityC: Double = 0
    private var lastDemandConditioningTime: Date?
    private let acousticRampGovernor = AcousticRampGovernor()

    private let pollInterval: TimeInterval = 1.0
    private let fastTemperatureEMAAlpha: Double = 0.16
    private let slowTemperatureEMAAlpha: Double = 0.045
    private let runtimeBandSize: Double = 0.06
    private let thermalDebtRiseRatePerTick: Double = 0.006
    private let thermalDebtFallRatePerTick: Double = 0.012
    private let thermalLeadSeconds: Double = 2.0
    private let maximumThermalLeadC: Double = 1.5
    private let minimumCommandPercentDelta: Double = 0.006
    private let demandNormalRiseVelocityPerSecond: Double = 0.08
    private let demandNormalFallVelocityPerSecond: Double = 0.06
    private let demandNormalAccelerationPerSecond: Double = 0.035
    private let demandTemperatureRiseVelocityCPerSecond: Double = 4.0
    private let demandTemperatureFallVelocityCPerSecond: Double = 3.0
    private let demandTemperatureAccelerationCPerSecond: Double = 1.6

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
                rampStateByFan.removeAll()
                lastCommandLogPercentByFan.removeAll()
                conditionedDemandPercent = nil
                conditionedDemandPercentVelocity = 0
                conditionedDemandTemperatureC = nil
                conditionedDemandTemperatureVelocityC = 0
                lastDemandConditioningTime = nil
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
                        baseCurvePercent: 0,
                        rawBaselinePercent: 0,
                        thermalDemandPercent: 0,
                        thermalDemandSource: .curve,
                        thermalDemandTemperatureC: maxCPUTemp > 0 ? maxCPUTemp : nil,
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
            let fastTrend = previousFastTemperature.map { fastTemp - $0 } ?? 0
            let slowTrend = previousSlowTemperature.map { slowTemp - $0 } ?? 0

            let boost = sharedConfig.loadBoostEnabled()
            let pressureTemperature = thermalPressureTemperature(
                rawTemperatureC: maxCPUTemp,
                fastTemperatureC: fastTemp,
                slowTemperatureC: slowTemp)
            let points = sharedConfig.loadCurve()
            let mode = sharedConfig.loadInterpolationMode()
            let baseCurvePercent = CurveInterpolation.evaluate(at: pressureTemperature, points: points, mode: mode)
            let curvePercent: Double
            if boost {
                curvePercent = 1.0
            } else {
                curvePercent = baseCurvePercent
            }

            var assistAppliedKinds: [LoadAssistKind] = []
            var assistFloorPercent: Double?
            var rawBaselinePercent = curvePercent
            var demandSource: ThermalDemandSource = .curve
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
                        demandSource = .assist
                    } else if assistFloor == rawBaselinePercent, assistFloor > 0 {
                        assistFloorPercent = assistFloor
                        assistAppliedKinds.append(kind)
                        demandSource = .assist
                    }
                }
            }
            let rawDemandPercent = max(0, min(1, rawBaselinePercent))
            let conditionedDemand = conditionedThermalDemand(
                rawPercent: boost ? 1.0 : rawDemandPercent,
                rawTemperatureC: pressureTemperature,
                now: now)

            let runtimeState: RuntimeBandState
            if boost {
                runtimeState = RuntimeBandState(
                    committedPercent: conditionedDemand.percent,
                    bandIndex: bandIndex(for: conditionedDemand.percent),
                    committedTemperatureC: maxCPUTemp,
                    baseCurvePercent: baseCurvePercent,
                    rawBaselinePercent: 1.0,
                    thermalDemandPercent: conditionedDemand.percent,
                    thermalDemandSource: .boost,
                    rawPressureTemperatureC: conditionedDemand.temperatureC,
                    mode: .rampingUp,
                    holdRemainingSeconds: 0
                )
            } else {
                let observedFanPercent = observedCurvePercent(fans: result.fans)
                runtimeState = bandControlledState(
                    rawBaselinePercent: rawBaselinePercent,
                    conditionedDemandPercent: conditionedDemand.percent,
                    conditionedDemandTemperatureC: conditionedDemand.temperatureC,
                    baseCurvePercent: baseCurvePercent,
                    demandSource: demandSource,
                    rawTemperatureC: maxCPUTemp,
                    fastTemperatureC: fastTemp,
                    slowTemperatureC: slowTemp,
                    cpuLoad: cpuLoad,
                    assistFloorPercent: assistFloorPercent,
                    observedFanPercent: observedFanPercent
                )
            }

            let assistSummary = assistAppliedKinds.map(\.rawValue).joined(separator: ",")
            log.debug(
                "agent.tick cpuTemp=\(Int(maxCPUTemp), privacy: .public)C cpuLoad=\(Int(cpuLoad), privacy: .public)% gpuLoad=\(Int(gpuLoad), privacy: .public)% raw=\(Int(runtimeState.rawBaselinePercent * 100), privacy: .public)% demand=\(Int(runtimeState.thermalDemandPercent * 100), privacy: .public)% demandSource=\(runtimeState.thermalDemandSource.rawValue, privacy: .public) committed=\(Int(runtimeState.committedPercent * 100), privacy: .public)% mode=\(runtimeState.mode.rawValue, privacy: .public) debt=\(Int(thermalDebt * 100), privacy: .public)% boost=\(boost, privacy: .public) assist=\(assistSummary, privacy: .public)"
            )

            var setFans: [(index: UInt, rpm: Float)] = []
            var autoFans: [UInt] = []
            for (fanIndex, fan) in result.fans.enumerated() {
                let command = fanCommandFor(
                    percent: runtimeState.committedPercent, minRPM: fan.minRPM, maxRPM: fan.maxRPM)
                let smoothedCommand =
                    rampGovernedCommand(
                        command,
                        for: UInt(fanIndex),
                        currentFan: fan,
                        currentTemperatureC: maxCPUTemp,
                        fastTrendCPerTick: fastTrend,
                        slowTrendCPerTick: slowTrend,
                        now: now)
                switch command {
                case .setRPM:
                    if case .setRPM(let rpm) = smoothedCommand {
                        setFans.append((index: UInt(fanIndex), rpm: rpm))
                    }
                case .auto:
                    rampStateByFan.removeValue(forKey: UInt(fanIndex))
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
                    baseCurvePercent: runtimeState.baseCurvePercent,
                    rawBaselinePercent: runtimeState.rawBaselinePercent,
                    thermalDemandPercent: runtimeState.thermalDemandPercent,
                    thermalDemandSource: runtimeState.thermalDemandSource,
                    thermalDemandTemperatureC: runtimeState.rawPressureTemperatureC,
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
        let baseCurvePercent: Double
        let rawBaselinePercent: Double
        let thermalDemandPercent: Double
        let thermalDemandSource: ThermalDemandSource
        let rawPressureTemperatureC: Double?
        let mode: AgentControllerMode
        let holdRemainingSeconds: Double
    }

    private struct RampCommandState {
        let rpm: Float
        let timestamp: Date
    }

    private func bandControlledState(
        rawBaselinePercent: Double,
        conditionedDemandPercent: Double,
        conditionedDemandTemperatureC: Double,
        baseCurvePercent: Double,
        demandSource: ThermalDemandSource,
        rawTemperatureC: Double,
        fastTemperatureC: Double,
        slowTemperatureC: Double,
        cpuLoad: Double,
        assistFloorPercent: Double?,
        observedFanPercent: Double?
    ) -> RuntimeBandState {
        let fastTrend = previousFastTemperature.map { fastTemperatureC - $0 } ?? 0
        let slowTrend = previousSlowTemperature.map { slowTemperatureC - $0 } ?? 0
        let baselinePercent = max(0, min(1, rawBaselinePercent))
        let targetPercent = conditionedDemandPercent
        let committedPercent = max(0, min(1, targetPercent))
        let observedPercent = observedFanPercent ?? committedPercent
        if observedPercent < committedPercent - 0.006 {
            controllerMode = .rampingUp
        } else if observedPercent > committedPercent + 0.006 {
            controllerMode = .rampingDown
        } else {
            controllerMode = .holding
        }

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
            steppedUp: (observedFanPercent ?? committedPercent) < committedPercent
        )
        return RuntimeBandState(
            committedPercent: committedPercent,
            bandIndex: nextBandIndex,
            committedTemperatureC: slowTemperatureC,
            baseCurvePercent: baseCurvePercent,
            rawBaselinePercent: baselinePercent,
            thermalDemandPercent: committedPercent,
            thermalDemandSource: demandSource,
            rawPressureTemperatureC: conditionedDemandTemperatureC,
            mode: controllerMode,
            holdRemainingSeconds: 0
        )
    }

    private func observedCurvePercent(fans: [FanInfo]) -> Double? {
        let percents = fans.compactMap { fan -> Double? in
            guard fan.maxRPM > fan.minRPM, fan.actualRPM > 0 else { return nil }
            let percent = Double((fan.actualRPM - fan.minRPM) / (fan.maxRPM - fan.minRPM))
            return max(0, min(1, percent))
        }
        guard !percents.isEmpty else { return nil }
        return percents.reduce(0, +) / Double(percents.count)
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
        return max(slowTemperatureC, ledTemperature)
    }

    private func conditionedThermalDemand(
        rawPercent: Double,
        rawTemperatureC: Double,
        now: Date
    ) -> (percent: Double, temperatureC: Double) {
        let targetPercent = max(0, min(1, rawPercent))
        guard
            let currentPercent = conditionedDemandPercent,
            let currentTemperature = conditionedDemandTemperatureC,
            let lastTime = lastDemandConditioningTime
        else {
            conditionedDemandPercent = targetPercent
            conditionedDemandPercentVelocity = 0
            conditionedDemandTemperatureC = rawTemperatureC
            conditionedDemandTemperatureVelocityC = 0
            lastDemandConditioningTime = now
            return (targetPercent, rawTemperatureC)
        }

        let dt = max(0.001, min(5.0, now.timeIntervalSince(lastTime)))
        let maxPercentVelocity =
            targetPercent >= currentPercent
            ? demandNormalRiseVelocityPerSecond
            : demandNormalFallVelocityPerSecond
        let nextPercent = accelerationLimitedStep(
            current: currentPercent,
            target: targetPercent,
            velocity: conditionedDemandPercentVelocity,
            maxVelocity: maxPercentVelocity,
            maxAcceleration: demandNormalAccelerationPerSecond,
            elapsedSeconds: dt)

        let maxTemperatureVelocity =
            rawTemperatureC >= currentTemperature
            ? demandTemperatureRiseVelocityCPerSecond
            : demandTemperatureFallVelocityCPerSecond
        let nextTemperature = accelerationLimitedStep(
            current: currentTemperature,
            target: rawTemperatureC,
            velocity: conditionedDemandTemperatureVelocityC,
            maxVelocity: maxTemperatureVelocity,
            maxAcceleration: demandTemperatureAccelerationCPerSecond,
            elapsedSeconds: dt)

        conditionedDemandPercent = nextPercent.value
        conditionedDemandPercentVelocity = nextPercent.velocity
        conditionedDemandTemperatureC = nextTemperature.value
        conditionedDemandTemperatureVelocityC = nextTemperature.velocity
        lastDemandConditioningTime = now
        return (nextPercent.value, nextTemperature.value)
    }

    private func accelerationLimitedStep(
        current: Double,
        target: Double,
        velocity: Double,
        maxVelocity: Double,
        maxAcceleration: Double,
        elapsedSeconds: Double
    ) -> (value: Double, velocity: Double) {
        let delta = target - current
        guard delta != 0, elapsedSeconds > 0 else {
            return (target, 0)
        }

        let direction = delta > 0 ? 1.0 : -1.0
        let clampedMaxVelocity = max(0, maxVelocity)
        let clampedAcceleration = max(0, maxAcceleration)
        let stoppingVelocity = sqrt(2 * clampedAcceleration * abs(delta))
        let desiredVelocity = direction * min(clampedMaxVelocity, stoppingVelocity)
        let nextVelocity = limitedStep(
            current: velocity,
            target: desiredVelocity,
            maximumDelta: clampedAcceleration * elapsedSeconds)
        let nextValue = current + nextVelocity * elapsedSeconds

        if (target - nextValue).sign != delta.sign || abs(target - nextValue) < 0.0001 {
            return (target, 0)
        }
        return (nextValue, nextVelocity)
    }

    private func limitedStep(current: Double, target: Double, maximumDelta: Double) -> Double {
        let delta = target - current
        guard abs(delta) > maximumDelta else { return target }
        return current + maximumDelta * (delta > 0 ? 1 : -1)
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
        let bandEscalationPressure = steppedUp ? 0.06 : 0.0

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

    /// Limit commanded RPM by elapsed time so config pushes and timer ticks
    /// share one acoustic envelope.
    private func rampGovernedCommand(
        _ command: FanCommand,
        for index: UInt,
        currentFan: FanInfo,
        currentTemperatureC: Double,
        fastTrendCPerTick: Double,
        slowTrendCPerTick: Double,
        now: Date
    ) -> FanCommand {
        switch command {
        case .auto:
            rampStateByFan.removeValue(forKey: index)
            return .auto
        case .setRPM(let requestedRPM):
            let baseline = commandBaselineRPM(
                fanIndex: index,
                requestedRPM: requestedRPM,
                currentFan: currentFan)
            let previousTimestamp = rampStateByFan[index]?.timestamp ?? now
            let decision = acousticRampGovernor.decision(
                for: AcousticRampGovernor.Input(
                    requestedRPM: requestedRPM,
                    baselineRPM: baseline,
                    elapsedSeconds: now.timeIntervalSince(previousTimestamp),
                    currentTemperatureC: currentTemperatureC,
                    fastTrendCPerTick: fastTrendCPerTick,
                    slowTrendCPerTick: slowTrendCPerTick,
                    thermalDebt: thermalDebt))
            rampStateByFan[index] = RampCommandState(rpm: decision.commandedRPM, timestamp: now)
            logRampDecisionIfNeeded(
                fanIndex: index,
                decision: decision,
                currentFan: currentFan,
                currentTemperatureC: currentTemperatureC)
            logCommandChangeIfNeeded(
                fanIndex: index,
                requestedRPM: requestedRPM,
                commandedRPM: decision.commandedRPM,
                currentFan: currentFan,
                currentTemperatureC: currentTemperatureC)
            return .setRPM(decision.commandedRPM)
        }
    }

    private func commandBaselineRPM(
        fanIndex: UInt,
        requestedRPM: Float,
        currentFan: FanInfo
    ) -> Float {
        if let previous = rampStateByFan[fanIndex] {
            return previous.rpm
        }

        let observedRPM = currentFan.actualRPM > 0 ? currentFan.actualRPM : currentFan.targetRPM
        guard currentFan.targetRPM > 0 else { return observedRPM }
        if requestedRPM < currentFan.targetRPM {
            return min(currentFan.targetRPM, observedRPM)
        }
        return max(currentFan.targetRPM, observedRPM)
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

    private func logRampDecisionIfNeeded(
        fanIndex: UInt,
        decision: AcousticRampGovernor.Decision,
        currentFan: FanInfo,
        currentTemperatureC: Double
    ) {
        guard decision.limited else { return }
        log.info(
            "agent.fan.ramp_governor fan=\(fanIndex, privacy: .public) requestedRPM=\(Int(decision.requestedRPM), privacy: .public) commandedRPM=\(Int(decision.commandedRPM), privacy: .public) baselineRPM=\(Int(decision.baselineRPM), privacy: .public) actualRPM=\(Int(currentFan.actualRPM), privacy: .public) elapsedMs=\(Int(decision.elapsedSeconds * 1000), privacy: .public) rateRPMPerSecond=\(Int(decision.rateRPMPerSecond), privacy: .public) tempC=\(Int(currentTemperatureC), privacy: .public) debt=\(Int(thermalDebt * 100), privacy: .public)% mode=\(controllerMode.rawValue, privacy: .public)"
        )
    }
}
