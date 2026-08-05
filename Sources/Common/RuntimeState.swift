//
//  RuntimeState.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-09.
//  Copyright © 2026, all rights reserved.
//

import Foundation

enum SetupActionAffordance: Codable, Sendable, Equatable {
  case approveBackgroundAgent
  case approveHelper
  case enableBackgroundAgent
  case installHelper
}

enum ControlActionAffordance: Codable, Sendable, Equatable {
  case disableBoost
  case enableBoost
  case turnOff
  case turnOn
}

enum RuntimeServiceRequirement: Codable, Sendable, Equatable {
  case approvalRequired
  case required
  case satisfied
}

enum SetupState: Codable, Sendable, Equatable {
  case backgroundAgentApproval(action: SetupActionAffordance)
  case backgroundAgentRequired(action: SetupActionAffordance)
  case helperApproval(action: SetupActionAffordance)
  case helperRequired(action: SetupActionAffordance)
  case ready

  static func resolve(
    backgroundAgent: RuntimeServiceRequirement,
    helper: RuntimeServiceRequirement
  ) -> SetupState {
    switch backgroundAgent {
    case .approvalRequired:
      return .backgroundAgentApproval(action: .approveBackgroundAgent)
    case .required:
      return .backgroundAgentRequired(action: .enableBackgroundAgent)
    case .satisfied:
      break
    }

    switch helper {
    case .approvalRequired:
      return .helperApproval(action: .approveHelper)
    case .required:
      return .helperRequired(action: .installHelper)
    case .satisfied:
      return .ready
    }
  }

  var isReady: Bool {
    if case .ready = self {
      return true
    }
    return false
  }
}

enum ControlState: Codable, Sendable, Equatable {
  case boost(action: ControlActionAffordance)
  case ownershipPreempted
  case readyOff(action: ControlActionAffordance)
  case readyOn(action: ControlActionAffordance)

  static func resolve(
    setupState: SetupState,
    curveActive: Bool,
    boostEnabled: Bool,
    ownershipPreempted: Bool
  ) -> ControlState {
    guard setupState.isReady else {
      return .readyOff(action: .turnOn)
    }
    if ownershipPreempted {
      return .ownershipPreempted
    }
    if boostEnabled {
      return .boost(action: .disableBoost)
    }
    if curveActive {
      return .readyOn(action: .turnOff)
    }
    return .readyOff(action: .turnOn)
  }
}

enum RuntimeHealth: Codable, Sendable, Equatable {
  case degraded(reason: RuntimeHealthIssue)
  case healthy
  case ownershipPreempted
  case stale

  var permitsFreshTelemetry: Bool {
    if case .stale = self {
      return false
    }
    return true
  }
}

enum RuntimeHealthIssue: Codable, Sendable, Equatable {
  case agentReportedFailure
  case helperUnavailable
  case setupIncomplete
  case snapshotUnavailable
}

struct RuntimeTelemetry: Codable, Sendable, Equatable {
  let timestamp: Date
  let helperReachable: Bool
  let curveActive: Bool
  let boostEnabled: Bool
  let governingTemperatureC: Double
  let committedTemperatureC: Double
  let rawPressureTemperatureC: Double?
  let cpuLoadPercent: Double
  let gpuLoadPercent: Double
  let effectiveCurvePercent: Double
  let baseCurvePercent: Double
  let rawBaselinePercent: Double
  let semanticDemandPercent: Double?
  let thermalDemandSource: ThermalDemandSource
  let semanticDemandTemperatureC: Double?
  let commandedTargetPercent: Double
  let commandedTargetTemperatureC: Double?
  let committedPercent: Double
  let controllerMode: AgentControllerMode
  let bandIndex: Int
  let holdRemainingSeconds: Double
  let assistFloorPercent: Double?
  let activeAssistKinds: [LoadAssistKind]
  let fans: [AgentFanSnapshot]

  init(snapshot: AgentSnapshot) {
    self.timestamp = snapshot.timestamp
    self.helperReachable = snapshot.helperReachable
    self.curveActive = snapshot.curveActive
    self.boostEnabled = snapshot.boostEnabled
    self.governingTemperatureC = snapshot.governingTemperatureC
    self.committedTemperatureC = snapshot.committedTemperatureC
    self.rawPressureTemperatureC = snapshot.rawPressureTemperatureC
    self.cpuLoadPercent = snapshot.cpuLoadPercent
    self.gpuLoadPercent = snapshot.gpuLoadPercent
    self.effectiveCurvePercent = snapshot.effectiveCurvePercent
    self.baseCurvePercent = snapshot.baseCurvePercent
    self.rawBaselinePercent = snapshot.rawBaselinePercent
    self.semanticDemandPercent = snapshot.semanticDemandPercent
    self.thermalDemandSource = snapshot.thermalDemandSource
    self.semanticDemandTemperatureC = snapshot.semanticDemandTemperatureC
    self.commandedTargetPercent = snapshot.commandedTargetPercent
    self.commandedTargetTemperatureC = snapshot.commandedTargetTemperatureC
    self.committedPercent = snapshot.committedPercent
    self.controllerMode = snapshot.controllerMode
    self.bandIndex = snapshot.bandIndex
    self.holdRemainingSeconds = snapshot.holdRemainingSeconds
    self.assistFloorPercent = snapshot.assistFloorPercent
    self.activeAssistKinds = snapshot.activeAssistKinds
    self.fans = snapshot.fans
  }

  func snapshot() -> AgentSnapshot {
    AgentSnapshot(
      timestamp: timestamp,
      helperReachable: helperReachable,
      curveActive: curveActive,
      boostEnabled: boostEnabled,
      governingTemperatureC: governingTemperatureC,
      committedTemperatureC: committedTemperatureC,
      rawPressureTemperatureC: rawPressureTemperatureC,
      cpuLoadPercent: cpuLoadPercent,
      gpuLoadPercent: gpuLoadPercent,
      effectiveCurvePercent: effectiveCurvePercent,
      baseCurvePercent: baseCurvePercent,
      rawBaselinePercent: rawBaselinePercent,
      semanticDemandPercent: semanticDemandPercent,
      thermalDemandSource: thermalDemandSource,
      semanticDemandTemperatureC: semanticDemandTemperatureC,
      commandedTargetPercent: commandedTargetPercent,
      commandedTargetTemperatureC: commandedTargetTemperatureC,
      committedPercent: committedPercent,
      controllerMode: controllerMode,
      bandIndex: bandIndex,
      holdRemainingSeconds: holdRemainingSeconds,
      assistFloorPercent: assistFloorPercent,
      activeAssistKinds: activeAssistKinds,
      fans: fans
    )
  }
}

enum TelemetryState: Codable, Sendable, Equatable {
  case degraded(telemetry: RuntimeTelemetry?, health: RuntimeHealth)
  case live(RuntimeTelemetry)
  case stale(telemetry: RuntimeTelemetry?)
  case unavailable

  static func resolve(telemetry: RuntimeTelemetry?, health: RuntimeHealth) -> TelemetryState {
    guard let telemetry else {
      if case .degraded = health {
        return .degraded(telemetry: nil, health: health)
      }
      if case .stale = health {
        return .stale(telemetry: nil)
      }
      return .unavailable
    }

    switch health {
    case .healthy, .ownershipPreempted:
      return .live(telemetry)
    case .stale:
      return .stale(telemetry: telemetry)
    case .degraded:
      return .degraded(telemetry: telemetry, health: health)
    }
  }

  var currentTelemetry: RuntimeTelemetry? {
    switch self {
    case .degraded(let telemetry, _):
      telemetry
    case .live(let telemetry):
      telemetry
    case .stale(let telemetry):
      telemetry
    case .unavailable:
      nil
    }
  }
}

struct RuntimeSetupInputs: Codable, Sendable, Equatable {
  let backgroundAgent: RuntimeServiceRequirement

  static let ready = RuntimeSetupInputs(backgroundAgent: .satisfied)
}

struct RuntimeStateInputs: Codable, Sendable, Equatable {
  let setup: RuntimeSetupInputs
  let systemHelper: SystemHelperRuntimeState
  let snapshot: AgentSnapshot?
  let now: Date
  let freshnessInterval: TimeInterval
  let agentReportedFailure: Bool
  let ownershipPreempted: Bool

  init(
    setup: RuntimeSetupInputs,
    systemHelper: SystemHelperRuntimeState,
    snapshot: AgentSnapshot?,
    now: Date = Date(),
    freshnessInterval: TimeInterval = 5,
    agentReportedFailure: Bool = false,
    ownershipPreempted: Bool = false
  ) {
    self.setup = setup
    self.systemHelper = systemHelper
    self.snapshot = snapshot
    self.now = now
    self.freshnessInterval = freshnessInterval
    self.agentReportedFailure = agentReportedFailure
    self.ownershipPreempted = ownershipPreempted
  }
}

private struct RuntimeHealthInputs: Codable, Sendable, Equatable {
  let setupState: SetupState
  let telemetry: RuntimeTelemetry?
  let now: Date
  let freshnessInterval: TimeInterval
  let agentReportedFailure: Bool
  let ownershipPreempted: Bool
}

struct RuntimeState: Codable, Sendable, Equatable {
  let setup: SetupState
  let systemHelper: SystemHelperRuntimeState
  let control: ControlState
  let telemetry: TelemetryState
  let health: RuntimeHealth

  var snapshot: AgentSnapshot? {
    telemetry.currentTelemetry?.snapshot()
  }

  static func resolve(_ inputs: RuntimeStateInputs) -> RuntimeState {
    let setupState = SetupState.resolve(
      backgroundAgent: inputs.setup.backgroundAgent,
      helper: inputs.systemHelper.setupRequirement
    )
    let agentSnapshot = inputs.snapshot
    let runtimeTelemetry = agentSnapshot.map(RuntimeTelemetry.init(snapshot:))
    let runtimeHealth = resolveHealth(
      inputs: RuntimeHealthInputs(
        setupState: setupState,
        telemetry: runtimeTelemetry,
        now: inputs.now,
        freshnessInterval: inputs.freshnessInterval,
        agentReportedFailure: inputs.agentReportedFailure,
        ownershipPreempted: inputs.ownershipPreempted
      )
    )
    let controlState = ControlState.resolve(
      setupState: setupState,
      curveActive: agentSnapshot?.curveActive ?? false,
      boostEnabled: agentSnapshot?.boostEnabled ?? false,
      ownershipPreempted: runtimeHealth == .ownershipPreempted
    )
    let telemetryState = TelemetryState.resolve(
      telemetry: runtimeTelemetry,
      health: runtimeHealth
    )
    return RuntimeState(
      setup: setupState,
      systemHelper: inputs.systemHelper,
      control: controlState,
      telemetry: telemetryState,
      health: runtimeHealth
    )
  }

  static func fromSharedDefaultsSnapshot(
    _ snapshot: AgentSnapshot?,
    setup: RuntimeSetupInputs = .ready,
    systemHelper: SystemHelperRuntimeState = .checking,
    now: Date = Date(),
    agentReportedFailure: Bool = false,
    ownershipPreempted: Bool = false
  ) -> RuntimeState {
    resolve(
      RuntimeStateInputs(
        setup: setup,
        systemHelper: systemHelper,
        snapshot: snapshot,
        now: now,
        agentReportedFailure: agentReportedFailure,
        ownershipPreempted: ownershipPreempted
      )
    )
  }

  private static func resolveHealth(inputs: RuntimeHealthInputs) -> RuntimeHealth {
    guard inputs.setupState.isReady else {
      return .degraded(reason: .setupIncomplete)
    }
    guard let currentTelemetry = inputs.telemetry else {
      return .degraded(reason: .snapshotUnavailable)
    }
    if inputs.ownershipPreempted {
      return .ownershipPreempted
    }
    if !currentTelemetry.helperReachable {
      return .degraded(reason: .helperUnavailable)
    }
    if inputs.agentReportedFailure {
      return .degraded(reason: .agentReportedFailure)
    }
    if inputs.now.timeIntervalSince(currentTelemetry.timestamp) >= inputs.freshnessInterval {
      return .stale
    }
    return .healthy
  }
}
