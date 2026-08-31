//
//  FanCurveAgentXPCService+SystemSettings.swift
//  FanCurveAgent
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-07-27.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

extension FanCurveAgentXPCService {
  func openSystemSettingsCommandResponse() async -> AgentCommandResponse {
    guard #available(macOS 13.0, *) else {
      return AgentCommandResponse(
        accepted: false,
        message: "System Settings action requires macOS 13"
      )
    }
    do {
      try await MainActor.run {
        try helperService.openSystemSettings()
      }
    } catch {
      agentXPCLog.error(
        "agent.xpc.command.system_settings.failed error=\(error.localizedDescription, privacy: .public) recovery=return-error"
      )
      return AgentCommandResponse(
        accepted: false,
        message: error.localizedDescription
      )
    }
    agentXPCLog.notice("agent.xpc.command.system_settings.opened owner=agent")
    return AgentCommandResponse(accepted: true, message: nil)
  }
}
