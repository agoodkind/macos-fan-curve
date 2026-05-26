//
//  DevScenario.swift
//  FanCurve
//
//  Copyright © 2026
//

#if DEBUG

    import Foundation

    /// A forced UI state for development and testing. Each case yields a runtime
    /// bundle (connection state, runtime state, snapshot) that drives the whole
    /// window through the agent client: the installation step is derived from the
    /// synthetic setup, and the sidebar, chart, and readouts follow. Compiled only
    /// into DEBUG builds.
    enum DevScenario: String, CaseIterable, Identifiable {
        case agentApproval
        case agentMissing
        case boost
        case degraded
        case healthy
        case helperApproval
        case helperRequired
        case ownershipPreempted
        case stale

        var id: String { rawValue }

        var menuTitle: String {
            switch self {
            case .agentApproval: return "Agent Approval Pending"
            case .agentMissing: return "Background Agent Missing"
            case .boost: return "Boost Active (live)"
            case .degraded: return "Agent Not Responding"
            case .healthy: return "Healthy (live)"
            case .helperApproval: return "Helper Approval Pending"
            case .helperRequired: return "Helper Required"
            case .ownershipPreempted: return "Ownership Preempted"
            case .stale: return "Stale Telemetry"
            }
        }

        /// Every scenario reports a connected agent so the installation step is
        /// derived from the synthetic setup rather than the real service status.
        var connectionState: FanCurveAgentConnectionState { .connected }

        /// Cases whose telemetry should advance over time so the dashboard moves.
        var animates: Bool {
            switch self {
            case .healthy, .boost, .ownershipPreempted: return true
            default: return false
            }
        }

        var naturalCurveActive: Bool {
            switch self {
            case .healthy, .stale, .ownershipPreempted, .boost: return true
            default: return false
            }
        }

        var naturalBoostEnabled: Bool { self == .boost }

        private var setupInputs: RuntimeSetupInputs {
            switch self {
            case .helperRequired:
                return RuntimeSetupInputs(backgroundAgent: .satisfied, helper: .required)
            case .helperApproval:
                return RuntimeSetupInputs(backgroundAgent: .satisfied, helper: .approvalRequired)
            case .agentMissing:
                return RuntimeSetupInputs(backgroundAgent: .required, helper: .satisfied)
            case .agentApproval:
                return RuntimeSetupInputs(backgroundAgent: .approvalRequired, helper: .satisfied)
            case .degraded, .stale, .ownershipPreempted, .healthy, .boost:
                return .ready
            }
        }

        private var providesTelemetry: Bool {
            switch self {
            case .stale, .ownershipPreempted, .healthy, .boost: return true
            default: return false
            }
        }

        private var snapshotAgeSeconds: TimeInterval { self == .stale ? 60 : 0 }

        private var agentReportedFailure: Bool { self == .degraded }

        private var preemptsOwnership: Bool { self == .ownershipPreempted }

        /// Builds the runtime state. `curveActive` and `boostEnabled` are passed in
        /// so a live toggle from the UI can override the scenario's natural values.
        func runtimeState(
            now: Date,
            phase: Double,
            curveActive: Bool,
            boostEnabled: Bool
        ) -> RuntimeState {
            RuntimeState.fromSharedDefaultsSnapshot(
                snapshot(
                    now: now,
                    phase: phase,
                    curveActive: curveActive,
                    boostEnabled: boostEnabled
                ),
                setup: setupInputs,
                now: now,
                agentReportedFailure: agentReportedFailure,
                ownershipPreempted: preemptsOwnership
            )
        }

        func snapshot(
            now: Date,
            phase: Double,
            curveActive: Bool,
            boostEnabled: Bool
        ) -> AgentSnapshot? {
            guard providesTelemetry else { return nil }
            let wave = (sin(phase / 6) + 1) / 2
            let governing = 45 + wave * 50
            let percent = max(0, min(1, (governing - 35) / (110 - 35)))
            let rpm = Float(2_300 + percent * 5_500)
            let fans = (0...1).map { index in
                AgentFanSnapshot(
                    index: index,
                    actualRPM: rpm,
                    targetRPM: rpm,
                    minRPM: 2_300,
                    maxRPM: 7_800,
                    manualMode: false
                )
            }
            return AgentSnapshot(
                timestamp: now.addingTimeInterval(-snapshotAgeSeconds),
                helperReachable: true,
                curveActive: curveActive,
                boostEnabled: boostEnabled,
                governingTemperatureC: governing,
                committedTemperatureC: governing,
                rawPressureTemperatureC: governing,
                cpuLoadPercent: 20 + wave * 60,
                gpuLoadPercent: 30 + (1 - wave) * 55,
                effectiveCurvePercent: percent,
                baseCurvePercent: percent,
                rawBaselinePercent: percent,
                semanticDemandPercent: percent,
                thermalDemandSource: boostEnabled ? .boost : .curve,
                semanticDemandTemperatureC: governing,
                commandedTargetPercent: percent,
                commandedTargetTemperatureC: governing,
                committedPercent: percent,
                controllerMode: .holding,
                bandIndex: 0,
                holdRemainingSeconds: 0,
                assistFloorPercent: nil,
                activeAssistKinds: [],
                fans: fans
            )
        }
    }

#endif
