//
//  GeneralSettingsView+Ownership.swift
//  FanCurve
//
//  Created by Codex <noreply@openai.com> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import SwiftUI

extension GeneralSettingsView {
  @ViewBuilder
  func activeControllerRow(_ row: AgentOwnershipEntry) -> some View {
    SettingsAccessoryRow(
      minimumLabelWidth: GeneralSettingsConstants.controllerRowMinimumLabelWidth,
      accessoryWidth: GeneralSettingsConstants.controllerRowAccessoryWidth
    ) {
      Text("Fan \(row.fanIndex)")
        .font(.caption)
        .foregroundStyle(.primary)
    } accessory: {
      VStack(
        alignment: .trailing,
        spacing: GeneralSettingsConstants.controllerRowVStackSpacing
      ) {
        Text(controllerDisplayName(row.clientName))
          .font(.caption)
          .foregroundStyle(.primary)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(row.clientName)
        Text("priority \(row.priority), \(formatAge(row.ageSeconds))")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.vertical, GeneralSettingsConstants.controllerRowVerticalPadding)
    .accessibilityIdentifier(
      AppAccessibilityIdentifier.Settings.ownershipRow(row.fanIndex)
    )
  }

  private func controllerDisplayName(_ clientName: String) -> String {
    if clientName == generatedAgentBundleID {
      return generatedAgentDisplayName
    }

    return clientName
  }

  private func formatAge(_ seconds: TimeInterval) -> String {
    if seconds < GeneralSettingsConstants.ageJustNowThresholdSeconds { return "just now" }
    if seconds < GeneralSettingsConstants.secondsPerMinute { return "\(Int(seconds))s ago" }
    let minutes = Int(seconds / GeneralSettingsConstants.secondsPerMinute)
    return "\(minutes)m ago"
  }
}
