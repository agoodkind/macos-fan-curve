//
//  FanOwnershipStatus.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-21.
//  Copyright © 2026
//
//  Observable wrapper around an SMCFanXPCClient that polls per fan
//  arbitration state for the Settings surface. Read only; does not
//  replace the agent's per tick write client. The poller only runs
//  while its owning view is visible.
//

import AppLog
import Combine
import Foundation
import SMCFanProtocol
import SMCFanXPCClient

private let log = AppLog.make(category: "FanOwnershipStatus")

/// One entry shown in the ownership disclosure. Mirrors
/// `SMCFanXPCClient.OwnershipEntry` but owned by @MainActor for SwiftUI.
struct ArbiterRow: Identifiable, Sendable {
  let id: UInt
  let fanIndex: UInt
  let clientName: String
  let priority: Int
  let ageSeconds: TimeInterval
}

@MainActor
final class FanOwnershipStatus: ObservableObject {
  @Published var reachable: Bool = false
  @Published var rows: [ArbiterRow] = []
  @Published var lastError: String?
  @Published var hasLoaded: Bool = false
  @Published var isMonitoring: Bool = false

  private let client: SMCFanXPCClient = {
    // See XPCClient: init throws for source compat only.
    try! SMCFanXPCClient(
      clientName: "\(generatedAppBundleID).settings",
      defaultPriority: 0
    )
  }()
  private var timer: Timer?

  // Owners must call `stopMonitoring` before dropping the last reference.
  // SwiftUI's `.onAppear` / `.onDisappear` pair already provides this for
  // the Settings screens. We cannot safely invalidate from a `deinit` here
  // because `Timer` is not `Sendable` and a `@MainActor` nonisolated
  // deinit is the default in Swift 6. A leaked timer ticks against a nil
  // `self?` via `[weak self]`, which is a no op rather than a crash.

  func startMonitoring(intervalSeconds: TimeInterval = 1.0) {
    self.stopMonitoring()
    self.isMonitoring = true
    log.debug(
      "ownership_status.start interval=\(intervalSeconds, privacy: .public)"
    )
    self.timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in await self?.tick() }
    }
    Task { @MainActor [weak self] in await self?.tick() }
  }

  func stopMonitoring() {
    self.timer?.invalidate()
    self.timer = nil
    self.isMonitoring = false
    log.debug("ownership_status.stop")
  }

  private func tick() async {
    do {
      let entries = try await client.getOwnership()
      let rows = entries.map {
        ArbiterRow(
          id: $0.fanIndex,
          fanIndex: $0.fanIndex,
          clientName: $0.clientName,
          priority: $0.priority,
          ageSeconds: $0.secondsSinceLastWrite
        )
      }
      self.rows = rows
      self.reachable = true
      self.lastError = nil
      self.hasLoaded = true
    } catch {
      self.reachable = false
      self.lastError = error.localizedDescription
      self.hasLoaded = true
      log.debug(
        "ownership_status.unreachable error=\(error.localizedDescription, privacy: .public)"
      )
    }
  }
}
