//
//  AgentPresence.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-08-02.
//  Copyright © 2026, all rights reserved.
//

import Foundation

// MARK: - AgentLivenessEvidence

/// What proved the Background Agent is answering, strongest evidence first.
///
/// An open XPC connection is direct proof and cannot go stale. The heartbeat
/// is weakest, because the app only learns its value when it polls. Judging
/// liveness by the heartbeat alone reported a fault whenever the poll itself
/// ran late, which says nothing about the Agent.
enum AgentLivenessEvidence: String, Equatable {
  case connection
  case heartbeat
  case unproven
}

// MARK: - AgentPresence

/// What the Background Agent row reports. The dot and the trailing words both
/// derive from this one value, so they cannot disagree the way parallel
/// condition chains could. VoiceOver speaks the words; the dot is decorative.
enum AgentPresence: String, Equatable, CaseIterable {
  case notInstalled
  case notResponding
  case running

  /// Wording a viewer reads instead of the dot's color. "Not responding"
  /// replaced "Installed", which described the registration rather than the
  /// problem and so read as success beside a warning color.
  var statusText: String {
    switch self {
    case .running: return "Running"
    case .notResponding: return "Not responding"
    case .notInstalled: return "Not Installed"
    }
  }
}

// MARK: - AgentPresenceResolver

/// Decides what the Agent row may claim, given one reading of the signals.
///
/// Pure on purpose. The reading is taken once, together, by the caller, so a
/// later render cannot re-age it. Passing `heartbeatAge` rather than a
/// timestamp is what makes that impossible to get wrong here.
enum AgentPresenceResolver {
  /// How old the heartbeat may be, when it is the only evidence available,
  /// before the Agent counts as silent.
  static let heartbeatFreshnessWindow: TimeInterval = 10

  struct Reading: Equatable {
    let registered: Bool
    let connected: Bool
    /// Seconds between the heartbeat's timestamp and the moment it was read.
    /// Nil when the Agent has never written one.
    let heartbeatAge: TimeInterval?
  }

  static func evidence(for reading: Reading) -> AgentLivenessEvidence {
    guard reading.registered else { return .unproven }
    if reading.connected { return .connection }
    guard let age = reading.heartbeatAge, age < heartbeatFreshnessWindow else {
      return .unproven
    }
    return .heartbeat
  }

  static func presence(for reading: Reading) -> AgentPresence {
    if evidence(for: reading) != .unproven { return .running }
    return reading.registered ? .notResponding : .notInstalled
  }
}
