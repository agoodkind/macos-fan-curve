//
//  SensorDashboardSidebar.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026
//

import SwiftUI

struct SensorDashboardSidebar: View {
    @ObservedObject var runtime: AgentSnapshotState
    @ObservedObject var curveModel: FanCurveModel
    @ObservedObject var installState: InstallationState
    let renderMode: AppRenderMode
    let unit: TemperatureUnit
    @Binding var boost: Bool
    let cpuLoadAssistEnabled: Bool
    let gpuLoadAssistEnabled: Bool
    let overdriveEnabled: Bool
    let underdriveEnabled: Bool
    let presentation: DashboardPresentationState

    var fanControlReady: Bool {
        presentation.controlState == .fanControl
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            heroSection
            usageSection
            fansSection
            Divider().opacity(0.15)
            controlsSection
            Spacer()
            statusBlock
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "thermometer.medium")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("CPU Temperature")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Circle()
                    .fill(tempColor)
                    .frame(width: 6, height: 6)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if let displayedTemperature {
                    Text("\(displayedTemperature)")
                        .font(.system(.largeTitle, design: .rounded).weight(.regular))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.38), value: displayedTemperature)
                    Text(unit.symbol)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else {
                    Text("--")
                        .font(.system(.largeTitle, design: .rounded).weight(.regular))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text("unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var usageSection: some View {
        let assistStates = activeAssistStates
        return VStack(spacing: 10) {
            usageBlock(
                label: "CPU",
                icon: "cpu",
                value: runtime.cpuLoadPercent,
                tint: Color.accentColor,
                assist: assistStates.first { $0.kind == .cpu }
            )
            usageBlock(
                label: "GPU",
                icon: "memorychip",
                value: runtime.gpuLoadPercent,
                tint: Color.accentColor.opacity(0.55),
                assist: assistStates.first { $0.kind == .gpu }
            )
        }
    }

    private var fansSection: some View {
        VStack(spacing: 10) {
            ForEach(runtime.fans) { fan in
                fanRow(fan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            }
        }
    }

    private var controlsSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fan Control")
                        .font(.body)
                    Text(fanControlStateLabel)
                        .font(.caption)
                        .foregroundColor(fanControlStateColor)
                    if fanControlReady, curveModel.isActive, !boost {
                        Text(controllerStateLabel)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if presentation.showsFanControlToggle {
                    Toggle("", isOn: $curveModel.isActive)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.regular)
                        .tint(Color.accentColor)
                        .disabled(boost)
                        .help(boost ? "Turn Boost off first to change this." : "")
                }
            }

            if presentation.helperActionVisible {
                setupButton
            } else if presentation.showsBoostControl, curveModel.isActive {
                boostButton
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                        )
                    )
            }
        }
    }
}
