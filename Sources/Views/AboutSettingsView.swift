//
//  AboutSettingsView.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026
//

import AppKit
import AppLog
import SwiftUI

private let aboutSettingsLog = AppLog.make(category: "AboutSettings")

struct AboutSettingsView: View {
    var body: some View {
        AboutContentView()
    }
}

/// Shared About pane. Used both as the Settings > About tab and as the
/// standalone About window that replaces macOS's default panel. Keeps
/// version, update check, author, and build hashes in one place.
struct AboutContentView: View {
    @EnvironmentObject private var appUpdater: AppUpdater

    var body: some View {
        Form {
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

            Section {
                Toggle(
                    "Automatically check for updates",
                    isOn: Binding(
                        get: { appUpdater.automaticallyChecksForUpdates },
                        set: { appUpdater.setAutomaticallyChecksForUpdates($0) })
                )
                .disabled(!appUpdater.isConfigured)

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
            } header: {
                Text("Software Updates")
            }

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
                    Button {
                        if let emailURL = URL(string: "mailto:alex@goodkind.io") {
                            NSWorkspace.shared.open(emailURL)
                        }
                    } label: {
                        Label("Email", systemImage: "envelope.fill")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("Email alex@goodkind.io")
                    .accessibilityLabel("Email")

                    Button {
                        if let websiteURL = URL(string: "https://goodkind.io") {
                            NSWorkspace.shared.open(websiteURL)
                        }
                    } label: {
                        Label("Website", systemImage: "globe")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("Open goodkind.io")
                    .accessibilityLabel("Website")

                    Button {
                        if let sourceURL = URL(string: "https://github.com/agoodkind") {
                            NSWorkspace.shared.open(sourceURL)
                        }
                    } label: {
                        Label("Source", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help("Open GitHub profile")
                    .accessibilityLabel("Source")
                }
            } header: {
                Text("Contact")
            }

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
        .formStyle(.grouped)
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity, alignment: .center)
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

    /// Compact hash pairing for the app and agent binaries.
    private var binariesLine: String {
        "FanCurve \(BuildHashes.appHash) · FanCurveAgent \(BuildHashes.agentHash)"
    }
    /// One line in the About section for a labeled build attribute. Uses
    /// a monospaced value so hashes and dates align.
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

/// Advanced risk-gated settings. Overdrive and Underdrive push beyond the
/// firmware reported safe range. Load Floor raises fans preemptively
/// under CPU load. All three share the "power user" framing.
