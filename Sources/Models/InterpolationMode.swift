//
//  InterpolationMode.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026
//

import AppLog

private let interpolationModeLog = AppLog.make(category: "InterpolationMode")

enum InterpolationMode: Codable, Sendable, Equatable {
    case catmullRom
    case linear

    init?(rawValue: String) {
        switch rawValue {
        case Self.catmullRom.rawValue: self = .catmullRom
        case Self.linear.rawValue: self = .linear
        default: return nil
        }
    }

    var rawValue: String {
        switch self {
        case .catmullRom: return "catmullRom"
        case .linear: return "linear"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let mode = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown interpolation mode: \(rawValue)"
            )
        }
        self = mode
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
