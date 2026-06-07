//
//  InterpolationMode.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026, all rights reserved.
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
    let decodedRawValue = try container.decode(String.self)
    guard let mode = Self(rawValue: decodedRawValue) else {
      interpolationModeLog.error(
        "interpolation_mode.decode_failed raw=\(decodedRawValue, privacy: .public) recovery=throw-data-corrupted"
      )
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unknown interpolation mode: \(decodedRawValue)"
      )
    }
    self = mode
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
