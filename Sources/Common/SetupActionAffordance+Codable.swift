//
//  SetupActionAffordance+Codable.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-10.
//  Copyright © 2026
//

import AppLog
import Foundation

private let runtimeStateCodableLog = AppLog.make(category: "RuntimeState")

extension SetupActionAffordance {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "approveBackgroundAgent":
            self = .approveBackgroundAgent
        case "approveHelper":
            self = .approveHelper
        case "enableBackgroundAgent":
            self = .enableBackgroundAgent
        case "installHelper":
            self = .installHelper
        default:
            runtimeStateCodableLog.error(
                "runtime_state.setup_action.decode_failed rawValue=\(rawValue, privacy: .public) recovery=reject-payload"
            )
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown setup action affordance: \(rawValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(encodedValue)
    }

    private var encodedValue: String {
        switch self {
        case .approveBackgroundAgent:
            return "approveBackgroundAgent"
        case .approveHelper:
            return "approveHelper"
        case .enableBackgroundAgent:
            return "enableBackgroundAgent"
        case .installHelper:
            return "installHelper"
        }
    }
}

extension ControlActionAffordance {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "disableBoost":
            self = .disableBoost
        case "enableBoost":
            self = .enableBoost
        case "turnOff":
            self = .turnOff
        case "turnOn":
            self = .turnOn
        default:
            runtimeStateCodableLog.error(
                "runtime_state.control_action.decode_failed rawValue=\(rawValue, privacy: .public) recovery=reject-payload"
            )
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown control action affordance: \(rawValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(encodedValue)
    }

    private var encodedValue: String {
        switch self {
        case .disableBoost:
            return "disableBoost"
        case .enableBoost:
            return "enableBoost"
        case .turnOff:
            return "turnOff"
        case .turnOn:
            return "turnOn"
        }
    }
}

extension RuntimeServiceRequirement {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "approvalRequired":
            self = .approvalRequired
        case "required":
            self = .required
        case "satisfied":
            self = .satisfied
        default:
            runtimeStateCodableLog.error(
                "runtime_state.service_requirement.decode_failed rawValue=\(rawValue, privacy: .public) recovery=reject-payload"
            )
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown runtime service requirement: \(rawValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(encodedValue)
    }

    private var encodedValue: String {
        switch self {
        case .approvalRequired:
            return "approvalRequired"
        case .required:
            return "required"
        case .satisfied:
            return "satisfied"
        }
    }
}

extension RuntimeHealthIssue {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "agentReportedFailure":
            self = .agentReportedFailure
        case "helperUnavailable":
            self = .helperUnavailable
        case "setupIncomplete":
            self = .setupIncomplete
        case "snapshotUnavailable":
            self = .snapshotUnavailable
        default:
            runtimeStateCodableLog.error(
                "runtime_state.health_issue.decode_failed rawValue=\(rawValue, privacy: .public) recovery=reject-payload"
            )
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown runtime health issue: \(rawValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(encodedValue)
    }

    private var encodedValue: String {
        switch self {
        case .agentReportedFailure:
            return "agentReportedFailure"
        case .helperUnavailable:
            return "helperUnavailable"
        case .setupIncomplete:
            return "setupIncomplete"
        case .snapshotUnavailable:
            return "snapshotUnavailable"
        }
    }
}
