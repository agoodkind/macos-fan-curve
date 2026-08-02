//
//  ServiceRowState.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026, all rights reserved.
//

import SwiftUI

/// How a service row reports a service's condition.
///
/// Color alone must never carry the meaning, so every case also supplies a
/// symbol and a spoken label. A viewer in grayscale, a viewer with color
/// blindness, and a VoiceOver listener all read the same state.
enum ServiceRowState: Equatable {
  case degraded
  case healthy
  case inactive

  var color: Color {
    switch self {
    case .healthy: return Color(nsColor: .systemGreen)
    case .degraded: return Color(nsColor: .systemOrange)
    case .inactive: return Color(nsColor: .systemGray)
    }
  }

  /// Distinct shapes, not three tints of one shape, so the states stay
  /// separable with color removed.
  var symbolName: String {
    switch self {
    case .healthy: return "checkmark.circle.fill"
    case .degraded: return "exclamationmark.triangle.fill"
    case .inactive: return "circle"
    }
  }

  var accessibilityLabel: String {
    switch self {
    case .healthy: return "Healthy"
    case .degraded: return "Needs attention"
    case .inactive: return "Inactive"
    }
  }
}

// MARK: - Agent presence

/// The dot's color for a presence. Wording, symbol, and spoken label all live
/// on `AgentPresence` itself, so every channel reads one value.
extension AgentPresence {
  var rowState: ServiceRowState {
    switch self {
    case .running: return .healthy
    case .notResponding: return .degraded
    case .notInstalled: return .inactive
    }
  }
}
