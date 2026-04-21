//
//  SMCDStatus.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-21.
//  Copyright © 2026
//
//  Observable wrapper around an SMCDClient that polls arbitration state
//  for the Settings and Arbiter screens. Does not replace the agent's
//  per tick client; this is a read only dashboard poller.
//

import AppLog
import Combine
import Foundation
import SMCDClient

private let log = AppLog.make(category: "SMCDStatus")

/// One entry shown in the Arbiter screen. Mirrors
/// `SMCDClient.OwnershipEntry` but owned by @MainActor for SwiftUI use.
struct ArbiterRow: Identifiable, Sendable {
  let id: UInt
  let fanIndex: UInt
  let clientName: String
  let priority: Int
  let ageSeconds: TimeInterval
}

@MainActor
final class SMCDStatus: ObservableObject {
  @Published var reachable: Bool = false
  @Published var rows: [ArbiterRow] = []
  @Published var lastError: String?

  private let client = SMCDClient(
    clientName: "fancurve-settings",
    defaultPriority: 0
  )
  private var timer: Timer?

  // Owners must call `stopMonitoring` before dropping the last reference.
  // SwiftUI's `.onAppear` / `.onDisappear` pair already provides this for
  // the Settings screens. We cannot safely invalidate from a `deinit` here
  // because `Timer` is not `Sendable` and a `@MainActor` nonisolated
  // deinit is the default in Swift 6. A leaked timer ticks against a nil
  // `self?` via `[weak self]`, which is a no op rather than a crash.

  func startMonitoring(intervalSeconds: TimeInterval = 1.0) {
    self.stopMonitoring()
    log.debug(
      "smcd_status.start interval=\(intervalSeconds, privacy: .public)"
    )
    self.timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in await self?.tick() }
    }
    Task { @MainActor [weak self] in await self?.tick() }
  }

  func stopMonitoring() {
    self.timer?.invalidate()
    self.timer = nil
    log.debug("smcd_status.stop")
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
    } catch {
      self.reachable = false
      self.lastError = error.localizedDescription
      log.debug(
        "smcd_status.unreachable error=\(error.localizedDescription, privacy: .public)"
      )
    }
  }
}
