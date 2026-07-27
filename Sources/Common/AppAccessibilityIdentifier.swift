//
//  AppAccessibilityIdentifier.swift
//  FanCurve
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

enum AppAccessibilityIdentifier {
  enum Application {
    static let mainWindow = "app.main-window"
    static let settingsButton = "app.button.settings"
    static let settingsCommand = "app.command.settings"
    static let aboutCommand = "app.command.about"
    static let quitCommand = "app.command.quit"
    static let settingsWindow = "app.settings-window"
    static let aboutWindow = "app.about-window"
    static let aboutContent = "app.about-content"
  }

  enum Setup {
    static let root = "setup.root"
    static let title = "setup.title"
    static let message = "setup.message"
    static let approvalGuide = "setup.approval-guide"
    static let action = "setup.action"
    static let error = "setup.error"
    static let sidebarAction = "setup.sidebar-action"
  }

  enum Dashboard {
    static let root = "dashboard.root"
    static let sidebar = "dashboard.sidebar"
    static let temperature = "dashboard.temperature"
    static let cpuLoad = "dashboard.load.cpu"
    static let gpuLoad = "dashboard.load.gpu"
    static let status = "dashboard.status"
    static let fanControl = "dashboard.fan-control"
    static let boost = "dashboard.boost"
    static let degraded = "dashboard.degraded"

    static func fanRow(_ index: Int) -> String {
      "dashboard.fan.\(index)"
    }
  }

  enum Curve {
    static let editor = "curve.editor"

    static func controlPoint(_ index: Int) -> String {
      "curve.control-point.\(index)"
    }
  }

  enum Settings {
    static let root = "settings.root"
    static let generalTab = "settings.tab.general"
    static let profilesTab = "settings.tab.profiles"
    static let advancedTab = "settings.tab.advanced"
    static let aboutTab = "settings.tab.about"
    static let applyInBackground = "settings.apply-in-background"
    static let backgroundAgentRow = "settings.background-agent.row"
    static let backgroundAgentStatus = "settings.background-agent.status"
    static let backgroundAgentAction = "settings.background-agent.action"
    static let helperRow = "settings.helper.row"
    static let helperStatus = "settings.helper.status"
    static let helperAction = "settings.helper.action"
    static let ownershipDisclosure = "settings.ownership.disclosure"
    static let ownershipStatus = "settings.ownership.status"
    static let learnAction = "settings.learn.action"

    static func ownershipRow(_ fanIndex: UInt) -> String {
      "settings.ownership.fan.\(fanIndex)"
    }
  }

  enum Learn {
    static let root = "learn.root"
    static let cancel = "learn.cancel"
    static let startSampling = "learn.start-sampling"
    static let startProbe = "learn.start-probe"
    static let confirmProbe = "learn.confirm-probe"
  }
}
