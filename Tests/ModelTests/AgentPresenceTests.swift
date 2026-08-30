//
//  AgentPresenceTests.swift
//  ModelTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-08-02.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import Nimble
import XCTest

@testable import FanCurveModels

/// What the Background Agent row is allowed to claim.
///
/// The row reported a fault while the app held an open connection to a healthy
/// Agent. Liveness was judged by the age of a heartbeat the app had copied on
/// its last refresh, so a refresh that ran late aged a working Agent into
/// looking dead. These lock the ranking that replaced it.
final class AgentPresenceTests: XCTestCase {
  private enum Fixture {
    /// Comfortably past the freshness window.
    static let staleHeartbeatAge: TimeInterval = 45
    static let freshHeartbeatAge: TimeInterval = 1
  }

  private func reading(
    registered: Bool,
    connected: Bool,
    heartbeatAge: TimeInterval?
  ) -> AgentPresenceResolver.Reading {
    AgentPresenceResolver.Reading(
      registered: registered,
      connected: connected,
      heartbeatAge: heartbeatAge
    )
  }

  /// The reported bug. Settings holds a connection while it is open, so a
  /// refresh that ran late must not turn the row orange.
  func testConnectedAgentWithStaleHeartbeatReportsRunning() {
    let input = reading(
      registered: true, connected: true, heartbeatAge: Fixture.staleHeartbeatAge)

    expect(AgentPresenceResolver.presence(for: input)) == .running
    expect(AgentPresenceResolver.evidence(for: input)) == .connection
  }

  /// With no connection the heartbeat is the only evidence left, and a recent
  /// one still proves the Agent is working.
  func testDisconnectedAgentWithFreshHeartbeatReportsRunning() {
    let input = reading(
      registered: true, connected: false, heartbeatAge: Fixture.freshHeartbeatAge)

    expect(AgentPresenceResolver.presence(for: input)) == .running
    expect(AgentPresenceResolver.evidence(for: input)) == .heartbeat
  }

  /// No connection and no recent heartbeat is the genuine fault the warning
  /// state exists to report.
  func testDisconnectedAgentWithStaleHeartbeatReportsNotResponding() {
    let input = reading(
      registered: true, connected: false, heartbeatAge: Fixture.staleHeartbeatAge)

    expect(AgentPresenceResolver.presence(for: input)) == .notResponding
    expect(AgentPresenceResolver.evidence(for: input)) == .unproven
  }

  /// An Agent that has never written a heartbeat, and is not connected, is
  /// silent rather than running.
  func testRegisteredAgentWithNoHeartbeatReportsNotResponding() {
    let input = reading(registered: true, connected: false, heartbeatAge: nil)

    expect(AgentPresenceResolver.presence(for: input)) == .notResponding
  }

  /// A connection proves the Agent is answering. It does not prove the Agent
  /// is registered, and the row must not claim an install that never happened.
  func testConnectedButUnregisteredAgentIsNotReportedInstalled() {
    let input = reading(
      registered: false, connected: true, heartbeatAge: Fixture.freshHeartbeatAge)

    expect(AgentPresenceResolver.presence(for: input)) == .notInstalled
  }

  /// The window is exclusive: only an age strictly inside it proves liveness,
  /// so a heartbeat exactly as old as the window counts as silent.
  func testHeartbeatExactlyAtWindowCountsAsSilent() {
    let atWindow = reading(
      registered: true,
      connected: false,
      heartbeatAge: AgentPresenceResolver.heartbeatFreshnessWindow
    )
    let justInside = reading(
      registered: true,
      connected: false,
      heartbeatAge: AgentPresenceResolver.heartbeatFreshnessWindow - 0.001
    )

    expect(AgentPresenceResolver.presence(for: atWindow)) == .notResponding
    expect(AgentPresenceResolver.presence(for: justInside)) == .running
  }

  /// VoiceOver speaks the status text, so distinct wording per state is what
  /// keeps the states separable without color.
  func testEveryPresenceHasDistinctWording() {
    let presences = AgentPresence.allCases

    expect(Set(presences.map(\.statusText)).count) == presences.count
  }

  /// Color is not information every viewer receives, so a warning state may
  /// never sit beside wording that reads as success.
  func testWarningStatesNeverReadAsHealthy() {
    let reassuring = ["Running", "Installed", "Ready", "OK"]

    for presence in [AgentPresence.notResponding, .notInstalled] {
      expect(reassuring).toNot(contain(presence.statusText))
    }
  }
}
