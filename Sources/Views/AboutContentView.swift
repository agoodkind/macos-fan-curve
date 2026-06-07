//
//  AboutContentView.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026, all rights reserved.
//

import AppKit
import AppLog
import SwiftUI

private let aboutSettingsLog = AppLog.make(category: "AboutSettings")

private enum AboutConstants {
  static let formMaxWidth: CGFloat = 680
  static let heroIconSize: CGFloat = 112
  static let heroStackSpacing: CGFloat = 16
  static let heroTitleStackSpacing: CGFloat = 4
  static let heroVerticalPadding: CGFloat = 4
  static let updateStatusAccessoryWidth: CGFloat = 112
  static let updateStatusContentSpacing: CGFloat = 2
  static let contactAccessoryWidth: CGFloat = 124
  static let contactContentSpacing: CGFloat = 2
  static let contactIconSpacing: CGFloat = 8
}

/// Shared About pane. Used both as the Settings > About tab and as the
/// standalone About window that replaces macOS's default panel. Keeps
/// version, update check, author, and build hashes in one place.
struct AboutContentView: View {
  @EnvironmentObject private var appUpdater: AppUpdater

  var body: some View {
    Form {
      heroSection
      softwareUpdatesSection
      contactSection
      buildDetailsSection
    }
    .formStyle(.grouped)
    .frame(maxWidth: AboutConstants.formMaxWidth)
    .frame(maxWidth: .infinity, alignment: .center)
  }

  private var heroSection: some View {
    Section {
      HStack(alignment: .center, spacing: AboutConstants.heroStackSpacing) {
        Image(.aboutHeroIcon)
          .resizable()
          .interpolation(.high)
          .aspectRatio(contentMode: .fit)
          .frame(width: AboutConstants.heroIconSize, height: AboutConstants.heroIconSize)

        VStack(alignment: .leading, spacing: AboutConstants.heroTitleStackSpacing) {
          Text("Fan Curve")
            .font(.title2.weight(.semibold))
          Text("Quiet fan control for Apple Silicon")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.vertical, AboutConstants.heroVerticalPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var softwareUpdatesSection: some View {
    Section {
      updatesToggle
      updateStatusContent
    } header: {
      Text("Software Updates")
    }
  }

  private var updatesToggle: some View {
    Toggle(
      "Automatically check for updates",
      isOn: Binding(
        get: { appUpdater.automaticallyChecksForUpdates },
        set: { appUpdater.setAutomaticallyChecksForUpdates($0) }
      )
    )
    .disabled(!appUpdater.isConfigured)
  }

  @ViewBuilder
  private var updateStatusContent: some View {
    if appUpdater.isConfigured {
      SettingsAccessoryRow(accessoryWidth: AboutConstants.updateStatusAccessoryWidth) {
        VStack(alignment: .leading, spacing: AboutConstants.updateStatusContentSpacing) {
          Label(updateStatusLabel, systemImage: updateStatusIcon)
            .foregroundColor(statusColor)
            .symbolRenderingMode(.hierarchical)
          Text("Updates are delivered automatically from goodkind.io.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } accessory: {
        Button("Check Now") { appUpdater.checkForUpdates() }
          .disabled(!appUpdater.canCheckForUpdates)
      }
    } else {
      Label("Software updates are available in release builds.", systemImage: "hammer")
        .foregroundStyle(.secondary)
        .symbolRenderingMode(.hierarchical)
    }
  }

  private var contactSection: some View {
    Section {
      SettingsAccessoryRow(accessoryWidth: AboutConstants.contactAccessoryWidth) {
        VStack(alignment: .leading, spacing: AboutConstants.contactContentSpacing) {
          Text("Alex Goodkind")
            .font(.body.weight(.semibold))
          Text("alex@goodkind.io")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } accessory: {
        HStack(alignment: .center, spacing: AboutConstants.contactIconSpacing) {
          iconButton(
            systemImage: "envelope.fill",
            helpText: "Email alex@goodkind.io",
            accessibilityLabel: "Email",
            urlString: "mailto:alex@goodkind.io"
          )
          iconButton(
            systemImage: "globe",
            helpText: "Open goodkind.io",
            accessibilityLabel: "Website",
            urlString: "https://goodkind.io"
          )
          iconButton(
            systemImage: "chevron.left.forwardslash.chevron.right",
            helpText: "Open GitHub profile",
            accessibilityLabel: "Source",
            urlString: "https://github.com/agoodkind"
          )
        }
      }
    } header: {
      Text("Contact")
    }
  }

  private var buildDetailsSection: some View {
    Section {
      buildInfoRow(label: "Version", value: semanticVersion)
      buildInfoRow(label: "Build", value: buildIdentifier)
      buildInfoRow(label: "Branch", value: generatedGitBranch)
      buildInfoRow(label: "Built", value: generatedBuildDate)
      buildInfoRow(label: "Binaries", value: binariesLine)
    } header: {
      Text("Build Details")
    }
  }

  private func iconButton(
    systemImage: String,
    helpText: String,
    accessibilityLabel: String,
    urlString: String
  ) -> some View {
    Button {
      openURL(urlString)
    } label: {
      Label(accessibilityLabel, systemImage: systemImage)
    }
    .labelStyle(.iconOnly)
    .buttonStyle(.bordered)
    .controlSize(.regular)
    .help(helpText)
    .accessibilityLabel(accessibilityLabel)
  }

  private func openURL(_ urlString: String) {
    guard let url = URL(string: urlString) else { return }
    aboutSettingsLog.notice(
      "about_settings.open_url destination=\(url.absoluteString, privacy: .public)"
    )
    NSWorkspace.shared.open(url)
  }

  private var updateStatusLabel: String {
    if appUpdater.canCheckForUpdates { return "Automatic updates are on" }
    return "Updater is starting"
  }

  private var semanticVersion: String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
  }

  private var buildIdentifier: String {
    generatedGitVersion
      .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
  }

  private var binariesLine: String {
    "FanCurve \(BuildHashes.appHash) · FanCurveAgent \(BuildHashes.agentHash)"
  }

  @ViewBuilder
  private func buildInfoRow(label: String, value: String) -> some View {
    SettingsKeyValueRow(label: label, value: value)
  }

  private var updateStatusIcon: String {
    "arrow.triangle.2.circlepath.circle"
  }

  private var statusColor: Color {
    Color(nsColor: .systemBlue)
  }
}
