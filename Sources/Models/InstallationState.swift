//
//  InstallationState.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import Combine
import Foundation
import ServiceManagement

/// Tracks whether the privileged helper and background agent are installed
/// and running. Drives the inline onboarding flow in the GUI.
@MainActor
final class InstallationState: ObservableObject {
  enum Step: Equatable {
    case checking
    case helperMissing
    case helperAwaitingApproval
    case agentMissing
    case agentAwaitingApproval
    case ready
  }

  @Published var step: Step = .checking
  @Published var lastError: String?
  @Published var helperReachable: Bool = false
  @Published var agentRawStatus: Int = 0

  private var timer: Timer?

  /// Convenience computed helpers for the Settings UI.
  var agentEnabled: Bool {
    guard #available(macOS 13.0, *) else { return false }
    return SMAppService.Status(rawValue: agentRawStatus) == .enabled
  }

  var agentStatusLabel: String {
    guard #available(macOS 13.0, *) else { return "Unavailable" }
    switch SMAppService.Status(rawValue: agentRawStatus) {
    case .enabled: return "Enabled"
    case .requiresApproval: return "Awaiting approval in System Settings"
    case .notFound: return "Not installed"
    case .notRegistered: return "Not registered"
    default: return "Unknown"
    }
  }

  func startMonitoring(xpcClient: XPCClient) {
    Task { await refresh(xpcClient: xpcClient) }
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
      Task { @MainActor in
        if let self {
          await self.refresh(xpcClient: xpcClient)
        }
      }
    }
  }

  func stopMonitoring() {
    timer?.invalidate()
    timer = nil
  }

  /// Attempts to register the agent via SMAppService. Idempotent.
  /// Opens System Settings if approval is required.
  func registerAgent() {
    guard #available(macOS 13.0, *) else { return }
    let service = SMAppService.agent(plistName: "\(generatedAgentBundleID).plist")
    do {
      try service.register()
      lastError = nil
    } catch {
      lastError = error.localizedDescription
    }
  }

  func openLoginItemsSettings() {
    if #available(macOS 13.0, *) {
      SMAppService.openSystemSettingsLoginItems()
    }
  }

  /// Unregister the agent. Stops it and removes its entry from Login Items.
  func unregisterAgent() {
    guard #available(macOS 13.0, *) else { return }
    let service = SMAppService.agent(plistName: "\(generatedAgentBundleID).plist")
    do {
      try service.unregister()
      lastError = nil
    } catch {
      lastError = error.localizedDescription
    }
  }

  /// Probes current installation status.
  private func refresh(xpcClient: XPCClient) async {
    let helperOK = await helperResponding(xpcClient: xpcClient)
    let agentStatus = currentAgentStatus()

    helperReachable = helperOK
    agentRawStatus = agentStatus.rawValue

    if !helperOK {
      step = .helperMissing
      return
    }

    switch agentStatus {
    case .enabled:
      step = .ready
    case .requiresApproval:
      step = .agentAwaitingApproval
    default:
      step = .agentMissing
    }
  }

  private func helperResponding(xpcClient: XPCClient) async -> Bool {
    do {
      _ = try await xpcClient.getFanCount()
      return true
    } catch {
      return false
    }
  }

  private func currentAgentStatus() -> SMAppService.Status {
    guard #available(macOS 13.0, *) else { return .notFound }
    return SMAppService.agent(plistName: "\(generatedAgentBundleID).plist").status
  }
}
