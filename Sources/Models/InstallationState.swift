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

  private var timer: Timer?

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

  /// Probes current installation status.
  private func refresh(xpcClient: XPCClient) async {
    let helperOK = await helperResponding(xpcClient: xpcClient)
    let agentStatus = currentAgentStatus()

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
