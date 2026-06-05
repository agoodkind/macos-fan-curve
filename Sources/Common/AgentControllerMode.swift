//
//  AgentControllerMode.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

private let agentControllerModeLog = AppLog.make(category: "AgentControllerMode")

enum AgentControllerMode: Codable, Sendable, Equatable {
    case holding
    case rampingDown
    case rampingUp

    init?(rawValue: String) {
        switch rawValue {
        case Self.holding.rawValue: self = .holding
        case Self.rampingDown.rawValue: self = .rampingDown
        case Self.rampingUp.rawValue: self = .rampingUp
        default:
            agentControllerModeLog.notice(
                "controller_mode.decode_unknown rawValue=\(rawValue, privacy: .public) recovery=reject-snapshot"
            )
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .holding: return "holding"
        case .rampingDown: return "rampingDown"
        case .rampingUp: return "rampingUp"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decodedRawValue = try container.decode(String.self)
        guard let mode = Self(rawValue: decodedRawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown controller mode: \(decodedRawValue)"
            )
        }
        self = mode
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
