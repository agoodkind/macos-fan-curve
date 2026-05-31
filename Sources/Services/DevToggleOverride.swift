//
//  DevToggleOverride.swift
//  FanCurve
//
//  Copyright © 2026, all rights reserved.
//

#if DEBUG

    /// Tri-state override for a simulated boolean control, used so a live toggle
    /// can override a scenario's natural value without an optional boolean.
    enum DevToggleOverride {
        case inherit
        case off
        case on

        func value(default fallback: Bool) -> Bool {
            switch self {
            case .inherit: return fallback
            case .on: return true
            case .off: return false
            }
        }
    }

#endif
