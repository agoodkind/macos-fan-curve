//
//  RuntimeState.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-09.
//  Copyright © 2026
//

import Foundation

enum SetupActionAffordance: String, Codable, Sendable, Equatable {
    case approveBackgroundAgent
    case approveHelper
    case enableBackgroundAgent
    case installHelper
}

enum ControlActionAffordance: String, Codable, Sendable, Equatable {
    case disableBoost
    case enableBoost
    case turnOff
    case turnOn
}

enum RuntimeServiceRequirement: String, Codable, Sendable, Equatable {
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
        switch helper {
        case .approvalRequired:
            return .helperApproval(action: .approveHelper)
        case .required:
            return .helperRequired(action: .installHelper)
        case .satisfied:
            break
        }

        switch backgroundAgent {
        case .approvalRequired:
            return .backgroundAgentApproval(action: .approveBackgroundAgent)
        case .required:
            return .backgroundAgentRequired(action: .enableBackgroundAgent)
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
}

enum RuntimeHealthIssue: String, Codable, Sendable, Equatable {
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
    let helper: RuntimeServiceRequirement

    static let ready = RuntimeSetupInputs(backgroundAgent: .satisfied, helper: .satisfied)
}

struct RuntimeStateInputs: Codable, Sendable, Equatable {
    let setup: RuntimeSetupInputs
    let snapshot: AgentSnapshot?
    let now: Date
    let freshnessInterval: TimeInterval
    let agentReportedFailure: Bool
    let ownershipPreempted: Bool

    init(
        setup: RuntimeSetupInputs,
        snapshot: AgentSnapshot?,
        now: Date = Date(),
        freshnessInterval: TimeInterval = 5,
        agentReportedFailure: Bool = false,
        ownershipPreempted: Bool = false
    ) {
        self.setup = setup
        self.snapshot = snapshot
        self.now = now
        self.freshnessInterval = freshnessInterval
        self.agentReportedFailure = agentReportedFailure
        self.ownershipPreempted = ownershipPreempted
    }
}

struct RuntimeState: Codable, Sendable, Equatable {
    let setup: SetupState
    let control: ControlState
    let telemetry: TelemetryState
    let health: RuntimeHealth

    var snapshot: AgentSnapshot? {
        telemetry.currentTelemetry?.snapshot()
    }

    static func resolve(_ inputs: RuntimeStateInputs) -> RuntimeState {
        let setupState = SetupState.resolve(
            backgroundAgent: inputs.setup.backgroundAgent,
            helper: inputs.setup.helper
        )
        let snapshot = inputs.snapshot
        let telemetry = snapshot.map(RuntimeTelemetry.init(snapshot:))
        let health = resolveHealth(
            setupState: setupState,
            telemetry: telemetry,
            now: inputs.now,
            freshnessInterval: inputs.freshnessInterval,
            agentReportedFailure: inputs.agentReportedFailure,
            ownershipPreempted: inputs.ownershipPreempted
        )
        let control = ControlState.resolve(
            setupState: setupState,
            curveActive: snapshot?.curveActive ?? false,
            boostEnabled: snapshot?.boostEnabled ?? false,
            ownershipPreempted: health == .ownershipPreempted
        )
        let telemetryState = TelemetryState.resolve(telemetry: telemetry, health: health)
        return RuntimeState(setup: setupState, control: control, telemetry: telemetryState, health: health)
    }

    static func fromSharedDefaultsSnapshot(
        _ snapshot: AgentSnapshot?,
        setup: RuntimeSetupInputs = .ready,
        now: Date = Date(),
        agentReportedFailure: Bool = false,
        ownershipPreempted: Bool = false
    ) -> RuntimeState {
        resolve(
            RuntimeStateInputs(
                setup: setup,
                snapshot: snapshot,
                now: now,
                agentReportedFailure: agentReportedFailure,
                ownershipPreempted: ownershipPreempted
            )
        )
    }

    private static func resolveHealth(
        setupState: SetupState,
        telemetry: RuntimeTelemetry?,
        now: Date,
        freshnessInterval: TimeInterval,
        agentReportedFailure: Bool,
        ownershipPreempted: Bool
    ) -> RuntimeHealth {
        guard setupState.isReady else {
            return .degraded(reason: .setupIncomplete)
        }
        guard let telemetry else {
            return .degraded(reason: .snapshotUnavailable)
        }
        if ownershipPreempted {
            return .ownershipPreempted
        }
        if !telemetry.helperReachable {
            return .degraded(reason: .helperUnavailable)
        }
        if agentReportedFailure {
            return .degraded(reason: .agentReportedFailure)
        }
        if now.timeIntervalSince(telemetry.timestamp) >= freshnessInterval {
            return .stale
        }
        return .healthy
    }
}
