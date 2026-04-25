//
//  AgentSnapshot.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-24.
//  Copyright © 2026
//

import AppKit
import AppLog
import Foundation

private let snapshotLog = AppLog.make(category: "AgentSnapshot")

enum AgentControllerMode: String, Codable, Sendable, Equatable {
  case holding
  case rampingUp
  case rampingDown
  case emergency
}

struct AgentFanSnapshot: Identifiable, Codable, Sendable, Equatable {
  var id: Int { index }

  let index: Int
  let actualRPM: Float
  let targetRPM: Float
  let minRPM: Float
  let maxRPM: Float
  let manualMode: Bool
}

struct AgentSnapshot: Codable, Sendable, Equatable {
  static let currentSchemaVersion = 2

  let schemaVersion: Int
  let timestampEpoch: Double
  let helperReachable: Bool
  let curveActive: Bool
  let boostEnabled: Bool
  let governingTemperatureC: Double
  let committedTemperatureC: Double
  let rawPressureTemperatureC: Double?
  let cpuLoadPercent: Double
  let gpuLoadPercent: Double
  let effectiveCurvePercent: Double
  let rawBaselinePercent: Double
  let committedPercent: Double
  let controllerMode: AgentControllerMode
  let bandIndex: Int
  let holdRemainingSeconds: Double
  let assistFloorPercent: Double?
  let activeAssistKinds: [LoadAssistKind]
  let fans: [AgentFanSnapshot]

  init(
    timestamp: Date,
    helperReachable: Bool,
    curveActive: Bool,
    boostEnabled: Bool,
    governingTemperatureC: Double,
    committedTemperatureC: Double,
    rawPressureTemperatureC: Double?,
    cpuLoadPercent: Double,
    gpuLoadPercent: Double,
    effectiveCurvePercent: Double,
    rawBaselinePercent: Double,
    committedPercent: Double,
    controllerMode: AgentControllerMode,
    bandIndex: Int,
    holdRemainingSeconds: Double,
    assistFloorPercent: Double?,
    activeAssistKinds: [LoadAssistKind],
    fans: [AgentFanSnapshot]
  ) {
    self.schemaVersion = Self.currentSchemaVersion
    self.timestampEpoch = timestamp.timeIntervalSince1970
    self.helperReachable = helperReachable
    self.curveActive = curveActive
    self.boostEnabled = boostEnabled
    self.governingTemperatureC = governingTemperatureC
    self.committedTemperatureC = committedTemperatureC
    self.rawPressureTemperatureC = rawPressureTemperatureC
    self.cpuLoadPercent = cpuLoadPercent
    self.gpuLoadPercent = gpuLoadPercent
    self.effectiveCurvePercent = effectiveCurvePercent
    self.rawBaselinePercent = rawBaselinePercent
    self.committedPercent = committedPercent
    self.controllerMode = controllerMode
    self.bandIndex = bandIndex
    self.holdRemainingSeconds = holdRemainingSeconds
    self.assistFloorPercent = assistFloorPercent
    self.activeAssistKinds = activeAssistKinds
    self.fans = fans
  }

  var timestamp: Date { Date(timeIntervalSince1970: timestampEpoch) }
}

enum AgentSnapshotStore {
  static func load(defaults: UserDefaults) -> AgentSnapshot? {
    guard
      let data = defaults.data(forKey: SharedConfigKeys.agentSnapshot),
      let snapshot = try? JSONDecoder().decode(AgentSnapshot.self, from: data),
      snapshot.schemaVersion == AgentSnapshot.currentSchemaVersion
    else { return nil }
    return snapshot
  }

  static func save(_ snapshot: AgentSnapshot, defaults: UserDefaults) {
    guard let data = try? JSONEncoder().encode(snapshot) else { return }
    defaults.set(data, forKey: SharedConfigKeys.agentSnapshot)
  }

  static func clear(defaults: UserDefaults) {
    defaults.removeObject(forKey: SharedConfigKeys.agentSnapshot)
  }
}

enum AgentSnapshotPush {
  static let notificationNameString = "io.goodkind.fancurve.snapshotChanged"

  static var notificationName: CFString { notificationNameString as CFString }

  static func post() {
    snapshotLog.debug("snapshot.pushed notification=\(notificationNameString, privacy: .public)")
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(notificationNameString as CFString),
      nil,
      nil,
      true)
  }
}

@MainActor
final class AgentSnapshotState: ObservableObject {
  private enum RefreshMode {
    case interactive
    case passiveVisible
    case occluded

    var intervalNanoseconds: UInt64 {
      switch self {
      case .interactive: return 180_000_000
      case .passiveVisible: return 1_200_000_000
      case .occluded: return 3_000_000_000
      }
    }
  }

  @Published private(set) var snapshot: AgentSnapshot?

  private let defaults: UserDefaults
  private var isAppActive = NSApp.isActive
  private var isAppHidden = NSApp.isHidden
  private var scheduledRefreshTask: Task<Void, Never>?
  private var didStart = false
  private var notificationTokens: [NSObjectProtocol] = []

  init(defaults: UserDefaults = UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard) {
    self.defaults = defaults
  }

  func start() {
    guard !didStart else { return }
    didStart = true
    snapshot = AgentSnapshotStore.load(defaults: defaults)
    isAppActive = NSApp.isActive
    isAppHidden = NSApp.isHidden

    let didBecomeActive = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.isAppActive = true
        self.scheduleReload(force: true)
      }
    }

    let didResignActive = NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.isAppActive = false
      }
    }

    let didHide = NotificationCenter.default.addObserver(
      forName: NSApplication.didHideNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.isAppHidden = true
      }
    }

    let didUnhide = NotificationCenter.default.addObserver(
      forName: NSApplication.didUnhideNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.isAppHidden = false
        self.scheduleReload(force: true)
      }
    }

    let windowNotifications: [Notification.Name] = [
      NSWindow.didChangeOcclusionStateNotification,
      NSWindow.didMiniaturizeNotification,
      NSWindow.didDeminiaturizeNotification,
      NSWindow.didBecomeKeyNotification,
      NSWindow.didResignKeyNotification
    ]

    let windowTokens = windowNotifications.map { name in
      NotificationCenter.default.addObserver(
        forName: name,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.handleVisibilityChange()
        }
      }
    }

    notificationTokens = [didBecomeActive, didResignActive, didHide, didUnhide] + windowTokens

    let token = Unmanaged.passUnretained(self).toOpaque()
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      token,
      { _, observer, _, _, _ in
        guard let observer else { return }
        let state = Unmanaged<AgentSnapshotState>.fromOpaque(observer).takeUnretainedValue()
        Task { @MainActor in state.handleSnapshotNotification() }
      },
      AgentSnapshotPush.notificationName,
      nil,
      .deliverImmediately)
  }

  func stop() {
    guard didStart else { return }
    didStart = false
    scheduledRefreshTask?.cancel()
    scheduledRefreshTask = nil
    for token in notificationTokens {
      NotificationCenter.default.removeObserver(token)
    }
    notificationTokens.removeAll()
    let token = Unmanaged.passUnretained(self).toOpaque()
    CFNotificationCenterRemoveObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      token,
      CFNotificationName(AgentSnapshotPush.notificationName),
      nil)
  }

  var governingTemperature: Double { snapshot?.governingTemperatureC ?? 0 }
  var committedTemperature: Double { snapshot?.committedTemperatureC ?? 0 }
  var rawPressureTemperature: Double? { snapshot?.rawPressureTemperatureC }
  var fans: [AgentFanSnapshot] { snapshot?.fans ?? [] }
  var cpuLoadPercent: Double { snapshot?.cpuLoadPercent ?? 0 }
  var gpuLoadPercent: Double { snapshot?.gpuLoadPercent ?? 0 }
  var effectiveCurvePercent: Double { snapshot?.effectiveCurvePercent ?? 0 }
  var rawBaselinePercent: Double { snapshot?.rawBaselinePercent ?? 0 }
  var committedPercent: Double { snapshot?.committedPercent ?? 0 }
  var controllerMode: AgentControllerMode { snapshot?.controllerMode ?? .holding }
  var bandIndex: Int { snapshot?.bandIndex ?? 0 }
  var holdRemainingSeconds: Double { snapshot?.holdRemainingSeconds ?? 0 }
  var assistFloorPercent: Double? { snapshot?.assistFloorPercent }
  var activeAssistKinds: [LoadAssistKind] { snapshot?.activeAssistKinds ?? [] }
  var helperReachable: Bool { snapshot?.helperReachable ?? false }
  var boostEnabled: Bool { snapshot?.boostEnabled ?? false }
  var curveActive: Bool { snapshot?.curveActive ?? false }
  var isFresh: Bool {
    guard let snapshot else { return false }
    return Date().timeIntervalSince(snapshot.timestamp) < 5
  }

  private func handleSnapshotNotification() {
    scheduleReload()
  }

  private func handleVisibilityChange() {
    if currentRefreshMode != .occluded {
      scheduleReload(force: true)
    }
  }

  private var currentRefreshMode: RefreshMode {
    if isAppHidden { return .occluded }
    let hasVisibleWindow = NSApp.windows.contains { window in
      window.isVisible
        && !window.isMiniaturized
        && window.occlusionState.contains(.visible)
    }
    if isAppActive && hasVisibleWindow { return .interactive }
    if hasVisibleWindow { return .passiveVisible }
    return .occluded
  }

  private func scheduleReload(force: Bool = false) {
    guard force || scheduledRefreshTask == nil else { return }
    let interval = currentRefreshMode.intervalNanoseconds
    scheduledRefreshTask?.cancel()
    scheduledRefreshTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: interval)
      guard !Task.isCancelled else { return }
      self?.scheduledRefreshTask = nil
      self?.reloadSnapshot()
    }
  }

  private func reloadSnapshot() {
    snapshot = AgentSnapshotStore.load(defaults: defaults)
  }
}
