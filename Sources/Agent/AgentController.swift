//
//  AgentController.swift
//  FanCurveAgent
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation
import SMCFanKit

let agentControllerLog = AppLog.make(category: "AgentController")

// MARK: - AgentRuntimeHealthOverride

struct AgentRuntimeHealthOverride: Sendable, Equatable {
  let now: Date
  let ownershipPreempted: Bool
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

  let fanHardware: any FanHardware
  let sharedConfig: SharedConfig
  let loadSampler = CPULoadSampler()
  let eventWriter = EventArtifactWriter()
  let tickCoordinator = TickCoordinator()
  lazy var heartbeatScheduler = TickHeartbeatScheduler(interval: heartbeatInterval) { [weak self] in
    self?.publishHeartbeat()
  }
  var timer: Timer?
  var cachedFanCount: UInt = 2
  var lastActivityState: ActivityState = .unknown
  var filteredTemperatureFast: Double?
  var filteredTemperatureSlow: Double?
  var previousFastTemperature: Double?
  var previousSlowTemperature: Double?
  var rampStateByFan: [UInt: RampCommandState] = [:]
  var rampSnapRequested = false
  var lastCurveShape: CurveShape?
  var lastPublishedSnapshot: AgentSnapshot?
  var controllerMode: AgentControllerMode = .holding
  var thermalDebt: Double = 0
  var lastCommandLogPercentByFan: [UInt: Double] = [:]
  var conditionedDemandPercent: Double?
  var conditionedDemandPercentVelocity: Double = 0
  var conditionedDemandTemperatureC: Double?
  var conditionedDemandTemperatureVelocityC: Double = 0
  var lastDemandConditioningTime: Date?
  var runtimeSetupProvider: (@Sendable (AgentSnapshot?) -> RuntimeSetupInputs)?
  var runtimeHealthOverrideProvider: (@Sendable (Date?) -> AgentRuntimeHealthOverride?)?
  var runtimeStateDidChange: (@Sendable (RuntimeState) -> Void)?
  let acousticRampGovernor = AcousticRampGovernor()

  let pollInterval: TimeInterval = 1.0
  /// Cadence for `heartbeatScheduler`, independent of `pollInterval`'s tick
  /// loop. Matches it by default; the two are decoupled on purpose and may
  /// diverge without affecting each other.
  let heartbeatInterval: TimeInterval = 1.0
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

  /// Catalog guess for this `hw.model`, before runtime resolution against
  /// the SMC's actual key list. `tempKeys`/`cpuTempKeys` start here and are
  /// narrowed once by `resolveSensorKeysIfNeeded()` on the first tick.
  static let catalogTempKeys: [String] = SensorCatalog.keysForCurrentHardware()
    .filter { $0.type == .temperature }
    .map(\.key)

  static let catalogCPUTempKeys: Set<String> = Set(
    SensorCatalog.keysForCurrentHardware()
      .filter { $0.type == .temperature && $0.group == .cpu }
      .map(\.key)
  )

  var tempKeys: [String] = AgentController.catalogTempKeys
  var cpuTempKeys: Set<String> = AgentController.catalogCPUTempKeys
  /// Guards `resolveSensorKeysIfNeeded()` so runtime key resolution against
  /// the SMC happens exactly once per process, on the first tick.
  var sensorKeysResolved = false

  init(
    fanHardware: any FanHardware = XPCClient(clientName: generatedAgentBundleID),
    sharedConfig: SharedConfig = SharedConfig()
  ) {
    self.fanHardware = fanHardware
    self.sharedConfig = sharedConfig
    agentControllerLog.notice("agent.hardware.configured owner=agent")
  }

  func start() {
    agentControllerLog.notice("agent.started pollInterval=\(pollInterval, privacy: .public)s")
    timer = Timer.scheduledTimer(
      withTimeInterval: pollInterval,
      repeats: true
    ) { [weak self] _ in
      self?.requestTick()
    }
    heartbeatScheduler.start()
    registerDarwinObserver()
    requestTick()
  }

  /// Stops tick scheduling without touching shared status or the XPC
  /// connection. Called first during shutdown so the 1 Hz tick loop stops
  /// competing with the reset-to-auto call for the same serialized XPC
  /// channel (see `AgentShutdownSequencer`).
  func stopTickTimer() {
    timer?.invalidate()
    timer = nil
    heartbeatScheduler.stop()
    unregisterDarwinObserver()
  }

  func stop() {
    stopTickTimer()
    sharedConfig.clearAgentStatus()
    fanHardware.shutdown()
    agentControllerLog.notice("agent.stopped")
  }

  /// Publishes liveness on `heartbeatScheduler`'s own cadence. Deliberately
  /// does not await anything: it must keep advancing even while a tick is
  /// stalled on a slow XPC round trip, since liveness ("is the process
  /// alive") and tick freshness ("how old is this data",
  /// `AgentSnapshot.timestamp`) are different questions that must not share
  /// one timestamp.
  func publishHeartbeat() {
    sharedConfig.writeAgentStatus(
      pid: ProcessInfo.processInfo.processIdentifier, lastTick: Date())
  }

  func resetAllFansToAuto() async {
    _ = await fanHardware.readAndApply(
      fanCount: cachedFanCount,
      tempKeys: [],
      autoFans: Array(0..<cachedFanCount)
    )
    agentControllerLog.notice("agent.fans.reset.auto")
  }

  func getOwnership() async throws -> [AgentOwnershipEntry] {
    agentControllerLog.debug("agent.hardware.ownership.requested")
    do {
      let rows = try await fanHardware.getOwnership()
      agentControllerLog.debug(
        "agent.hardware.ownership.returned count=\(rows.count, privacy: .public)"
      )
      return rows
    } catch {
      agentControllerLog.notice(
        "agent.hardware.ownership.failed error=\(error.localizedDescription, privacy: .public) recovery=propagate"
      )
      throw error
    }
  }

  func setFanRPM(_ fanIndex: UInt, rpm: Float) async throws {
    agentControllerLog.info(
      "agent.hardware.rpm.requested fan=\(fanIndex, privacy: .public) rpm=\(rpm, privacy: .public)"
    )
    do {
      try await fanHardware.setFanRPM(fanIndex, rpm: rpm, priority: nil)
      agentControllerLog.info(
        "agent.hardware.rpm.succeeded fan=\(fanIndex, privacy: .public) rpm=\(rpm, privacy: .public)"
      )
    } catch {
      agentControllerLog.notice(
        "agent.hardware.rpm.failed fan=\(fanIndex, privacy: .public) rpm=\(rpm, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=propagate"
      )
      throw error
    }
  }

  func setFanAuto(_ fanIndex: UInt) async throws {
    agentControllerLog.info(
      "agent.hardware.auto.requested fan=\(fanIndex, privacy: .public)"
    )
    do {
      try await fanHardware.setFanAuto(fanIndex, priority: nil)
      agentControllerLog.info(
        "agent.hardware.auto.succeeded fan=\(fanIndex, privacy: .public)"
      )
    } catch {
      agentControllerLog.notice(
        "agent.hardware.auto.failed fan=\(fanIndex, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=propagate"
      )
      throw error
    }
  }

  func currentRuntimeStateForXPC() -> RuntimeState {
    let healthOverride = runtimeHealthOverrideProvider?(lastPublishedSnapshot?.timestamp)
    return RuntimeState.fromSharedDefaultsSnapshot(
      lastPublishedSnapshot,
      setup: runtimeSetupProvider?(lastPublishedSnapshot) ?? .ready,
      now: healthOverride?.now ?? Date(),
      ownershipPreempted: healthOverride?.ownershipPreempted ?? false
    )
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
