//
//  AboutContentView.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026
//

import AppKit
import AppLog
import SwiftUI

private let aboutSettingsLog = AppLog.make(category: "AboutSettings")

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
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var heroSection: some View {
        Section {
            HStack(alignment: .center, spacing: 16) {
                Image(.aboutHeroIcon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 112, height: 112)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Fan Curve")
                        .font(.title2.weight(.semibold))
                    Text("Quiet fan control for Apple Silicon")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 4)
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
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label(updateStatusLabel, systemImage: updateStatusIcon)
                        .foregroundColor(statusColor)
                        .symbolRenderingMode(.hierarchical)
                    Text("Updates are delivered automatically from goodkind.io.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

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
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Alex Goodkind")
                        .font(.body.weight(.semibold))
                    Text("alex@goodkind.io")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
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
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var updateStatusIcon: String {
        "arrow.triangle.2.circlepath.circle"
    }

    private var statusColor: Color {
        Color(nsColor: .systemBlue)
    }
}
