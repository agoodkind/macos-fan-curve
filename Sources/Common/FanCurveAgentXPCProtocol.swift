//
//  FanCurveAgentXPCProtocol.swift
//  FanCurve
//
//  Copyright © 2026
//

import Foundation

enum FanCurveAgentXPC {
    static let serviceName = generatedAgentBundleID
}

/// App-facing XPC protocol exported by FanCurveAgent.
/// Payloads are kept Objective-C bridgeable so the protocol can be used by NSXPCConnection.
@objc public protocol FanCurveAgentXPCProtocol {
    /// Returns an encoded `RuntimeState`.
    func getCurrentState(reply: @escaping @Sendable (Bool, Data?, String?) -> Void)

    /// Requests an immediate agent tick without waiting for the polling interval.
    func requestRefresh(reply: @escaping @Sendable (Bool, String?) -> Void)

    /// Updates whether the agent should apply fan control.
    func setFanControlEnabled(
        _ enabled: Bool,
        reply: @escaping @Sendable (Bool, String?) -> Void
    )

    /// Updates whether user boost is enabled.
    func setBoostEnabled(
        _ enabled: Bool,
        reply: @escaping @Sendable (Bool, String?) -> Void
    )

    /// Stores an encoded curve payload. The concrete curve/runtime payload type is owned
    /// by the RuntimeState worker and should replace this opaque data boundary later.
    func setCurve(
        _ curveData: Data,
        reply: @escaping @Sendable (Bool, String?) -> Void
    )
}
