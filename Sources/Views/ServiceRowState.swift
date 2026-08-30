//
//  ServiceRowState.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026, all rights reserved.
//

import SwiftUI

/// How a service row reports a service's condition.
///
/// Color alone must never carry the meaning, so every case also supplies a
/// symbol. The row's status text carries the state for VoiceOver; the symbol
/// is decorative there, so the spoken state and the visible words cannot
/// disagree.
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

}

// MARK: - Agent presence

/// The dot for a presence. The wording lives on `AgentPresence` itself, so
/// every channel reads one value.
extension AgentPresence {
  var rowState: ServiceRowState {
    switch self {
    case .running: return .healthy
    case .notResponding: return .degraded
    case .notInstalled: return .inactive
    }
  }
}
