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

let agentControllerLog = AppLog.make(category: "AgentController")

actor TickCoordinator {
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
    enum ActivityState {
        case inactive
        case active
        case unknown
    }

    let xpcClient = XPCClient(clientName: generatedAgentBundleID)
    let sharedConfig = SharedConfig()
    let loadSampler = CPULoadSampler()
    let eventWriter = EventArtifactWriter()
    let tickCoordinator = TickCoordinator()
    var timer: Timer?
    var cachedFanCount: UInt = 2
    var lastActivityState: ActivityState = .unknown
    var filteredTemperatureFast: Double?
    var filteredTemperatureSlow: Double?
    var previousFastTemperature: Double?
    var previousSlowTemperature: Double?
    var rampStateByFan: [UInt: RampCommandState] = [:]
    var lastPublishedSnapshot: AgentSnapshot?
    var controllerMode: AgentControllerMode = .holding
    var thermalDebt: Double = 0
    var lastCommandLogPercentByFan: [UInt: Double] = [:]
    var conditionedDemandPercent: Double?
    var conditionedDemandPercentVelocity: Double = 0
    var conditionedDemandTemperatureC: Double?
    var conditionedDemandTemperatureVelocityC: Double = 0
    var lastDemandConditioningTime: Date?
    let acousticRampGovernor = AcousticRampGovernor()

    let pollInterval: TimeInterval = 1.0
    let fastTemperatureEMAAlpha: Double = 0.16
    let slowTemperatureEMAAlpha: Double = 0.045
    let runtimeBandSize: Double = 0.06
    let thermalDebtRiseRatePerTick: Double = 0.006
    let thermalDebtFallRatePerTick: Double = 0.012
    let thermalLeadSeconds: Double = 2.0
    let maximumThermalLeadC: Double = 1.5
    let minimumCommandPercentDelta: Double = 0.006
    let demandNormalRiseVelocityPerSecond: Double = 0.08
    let demandNormalFallVelocityPerSecond: Double = 0.06
    let demandNormalAccelerationPerSecond: Double = 0.035
    let demandTemperatureRiseVelocityCPerSecond: Double = 4.0
    let demandTemperatureFallVelocityCPerSecond: Double = 3.0
    let demandTemperatureAccelerationCPerSecond: Double = 1.6

    let tempKeys: [String] = SensorCatalog.keysForCurrentHardware()
        .filter { $0.type == .temperature }
        .map(\.key)

    let cpuTempKeys: Set<String> = Set(
        SensorCatalog.keysForCurrentHardware()
            .filter { $0.type == .temperature && $0.group == .cpu }
            .map(\.key)
    )

    func start() {
        agentControllerLog.notice("agent.started pollInterval=\(pollInterval, privacy: .public)s")
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
        agentControllerLog.notice("agent.stopped")
    }

    func resetAllFansToAuto() async {
        _ = await xpcClient.readAndApply(
            fanCount: cachedFanCount,
            tempKeys: [],
            autoFans: Array(0..<cachedFanCount)
        )
        agentControllerLog.notice("agent.fans.reset.auto")
    }

    func registerDarwinObserver() {
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
            .deliverImmediately
        )
        agentControllerLog.info(
            "agent.darwin.observer.registered name=\(SharedConfigPush.notificationNameString, privacy: .public)"
        )
    }

    func unregisterDarwinObserver() {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer
        )
    }
}
