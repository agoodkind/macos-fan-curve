//
//  DevScenario.swift
//  FanCurve
//
//  Copyright © 2026, all rights reserved.
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

        // MARK: - Scenario simulation constants

        private enum SimConstants {
            // Temperature simulation
            static let governingTempBaseC: Double = 45
            static let governingTempWaveAmplitude: Double = 50
            static let percentTempLowerBoundC: Double = 35
            static let percentTempUpperBoundC: Double = 110

            // Fan RPM
            static let fanBaseRPM: Float = 2_300
            static let fanRPMWaveRange: Double = 5_500
            static let fanMinRPM: Float = 2_300
            static let fanMaxRPM: Float = 7_800

            // Load percent simulation
            static let cpuLoadBasePercent: Double = 20
            static let cpuLoadWaveAmplitude: Double = 60
            static let gpuLoadBasePercent: Double = 30
            static let gpuLoadWaveAmplitude: Double = 55

            // Wave period divisor
            static let wavePhraseDivisor: Double = 6

            // Divisor that maps the raw sine range [-1, 1] into the unit interval [0, 1]
            static let sineUnitNormalizer: Double = 2

            // Stale snapshot age
            static let staleSnapshotAgeSeconds: TimeInterval = 60
        }

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

        private var snapshotAgeSeconds: TimeInterval {
            self == .stale ? SimConstants.staleSnapshotAgeSeconds : 0
        }

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
            let wave =
                (sin(phase / SimConstants.wavePhraseDivisor) + 1) / SimConstants.sineUnitNormalizer
            let governing =
                SimConstants.governingTempBaseC + wave * SimConstants.governingTempWaveAmplitude
            let tempRange =
                SimConstants.percentTempUpperBoundC - SimConstants.percentTempLowerBoundC
            let percent = max(
                0, min(1, (governing - SimConstants.percentTempLowerBoundC) / tempRange))
            let rpm = Float(Double(SimConstants.fanMinRPM) + percent * SimConstants.fanRPMWaveRange)
            let fans = (0...1).map { index in
                AgentFanSnapshot(
                    index: index,
                    actualRPM: rpm,
                    targetRPM: rpm,
                    minRPM: SimConstants.fanMinRPM,
                    maxRPM: SimConstants.fanMaxRPM,
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
                cpuLoadPercent: SimConstants.cpuLoadBasePercent + wave
                    * SimConstants.cpuLoadWaveAmplitude,
                gpuLoadPercent: SimConstants.gpuLoadBasePercent + (1 - wave)
                    * SimConstants.gpuLoadWaveAmplitude,
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
