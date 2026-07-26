//
//  AppUpdater.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-24.
//

import AppLog
import Combine
import Sparkle

private let appUpdaterLog = AppLog.make(category: "AppUpdater")

@MainActor
final class AppUpdater: ObservableObject {
  @Published private(set) var canCheckForUpdates = false
  @Published private(set) var automaticallyChecksForUpdates = false

  private(set) var updaterController: SPUStandardUpdaterController?

  var isConfigured: Bool {
    Self.updatesEnabledForBuild
      && !generatedSparkleFeedURL.isEmpty
      && !generatedSparklePublicEDKey.isEmpty
  }

  init() {
    guard Self.updatesEnabledForBuild else {
      appUpdaterLog.info("app_updater.disabled reason=debug_build")
      return
    }
    guard isConfigured else {
      appUpdaterLog.notice("app_updater.disabled reason=missing_release_configuration")
      return
    }

    let controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil)
    updaterController = controller
    appUpdaterLog.info("app_updater.started")

    controller.updater.publisher(for: \.canCheckForUpdates)
      .receive(on: RunLoop.main)
      .assign(to: &$canCheckForUpdates)

    controller.updater.publisher(for: \.automaticallyChecksForUpdates)
      .receive(on: RunLoop.main)
      .assign(to: &$automaticallyChecksForUpdates)
  }

  func checkForUpdates() {
    updaterController?.checkForUpdates(nil)
  }

  func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
    updaterController?.updater.automaticallyChecksForUpdates = enabled
  }

  private static var updatesEnabledForBuild: Bool {
    #if DEBUG
      false
    #else
      true
    #endif
  }
}
