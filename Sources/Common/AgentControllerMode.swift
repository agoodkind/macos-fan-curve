//
//  AgentControllerMode.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026
//

import AppLog
import Foundation

private let agentControllerModeLog = AppLog.make(category: "AgentControllerMode")

enum AgentControllerMode: Codable, Sendable, Equatable {
    case emergency
    case holding
    case rampingDown
    case rampingUp

    init?(rawValue: String) {
        switch rawValue {
        case Self.emergency.rawValue: self = .emergency
        case Self.holding.rawValue: self = .holding
        case Self.rampingDown.rawValue: self = .rampingDown
        case Self.rampingUp.rawValue: self = .rampingUp
        default: return nil
        }
    }

    var rawValue: String {
        switch self {
        case .emergency: return "emergency"
        case .holding: return "holding"
        case .rampingDown: return "rampingDown"
        case .rampingUp: return "rampingUp"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let mode = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown controller mode: \(rawValue)"
            )
        }
        self = mode
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
