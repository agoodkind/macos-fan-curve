//
//  DevScenarioStore.swift
//  FanCurve
//
//  Copyright © 2026
//

#if DEBUG

    import Combine
    import Foundation

    /// Holds the active developer scenario for the running app. Seeded from the
    /// launch flag so a scenario can be set headlessly, and writable by the
    /// in-app Debug menu so scenarios can be switched live. Compiled only into
    /// DEBUG builds.
    @MainActor
    final class DevScenarioStore: ObservableObject {
        static let shared = DevScenarioStore()

        @Published var current: DevScenario?

        private init() {
            let raw = DevOverrides.stringFlag(
                environment: "FANCURVE_DEV_SCENARIO", defaultsKey: "FanCurveDevScenario")
            current = raw.flatMap(DevScenario.init(rawValue:))
        }
    }

#endif
