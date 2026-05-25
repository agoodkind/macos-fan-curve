//
//  LearnSheet.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import AppLog
import SwiftUI

let learnSheetLog = AppLog.make(category: "LearnSheet")

struct LearnSheet: View {
    @ObservedObject var curveModel: FanCurveModel
    @ObservedObject var sensorState: SensorState
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var agentClient: FanCurveAgentClient

    @StateObject private var learner = CurveLearner()
    @StateObject private var workload = WorkloadGenerator()

    @State private var runCPU = true
    @State private var runGPU = true
    @State private var priorFanControl = false
    @State private var confirmProbe = false
    @State private var publishError: String?

    private let durationSeconds = 180

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            sheetBody
            Divider()
            footer
        }
        .padding(20)
        .frame(width: 480)
        .fancurveGlassCard(cornerRadius: 14)
        .onDisappear {
            workload.stop()
            learner.cancel()
            learner.cancelProbe()
            // Restore fan 0 to auto in case the probe left it in manual mode.
            Task {
                do {
                    try await agentClient.setFanAuto(0)
                } catch {
                    learnSheetLog.notice(
                        "learn.dismiss.auto_restore_failed fan=0 error=\(error.localizedDescription, privacy: .public) recovery=next-agent-tick"
                    )
                }
            }
            curveModel.isActive = priorFanControl
        }
        .alert("Probe maximum fan RPM?", isPresented: $confirmProbe) {
            Button("Start Probe", role: .destructive) { startProbe() }
            Button("Cancel", role: .cancel) {
                confirmProbe = false
            }
        } message: {
            Text(
                "Fan 0 will spin at its mechanical limit for 15 seconds. Expect loud noise. "
                    + "The reading becomes the new Overdrive target."
            )
        }
    }

    private func publishResults() {
        let curve = learner.learnedCurve
        guard !curve.isEmpty else { return }
        do {
            try LearnResultPublisher.publish(
                curve: curve,
                minTemp: learner.minTempSampled,
                maxTemp: learner.maxTempSampled,
                sampleCount: learner.samplesCollected,
                probe: learner.probeResult
            )
            publishError = nil
        } catch {
            publishError = "Could not open pull request: \(error.localizedDescription)"
            learnSheetLog.error(
                "learn.publish.failed error=\(error.localizedDescription, privacy: .public) recovery=show-alert"
            )
        }
    }

    private func startProbe() {
        learner.startProbe(
            fanIndex: 0,
            sensorState: sensorState
        ) { index, rpm in
            try await agentClient.setFanRPM(index, rpm: rpm)
        }
        // Restore auto when the probe finishes. We don't know the exact
        // moment inside the learner, so schedule based on its total seconds.
        let delay = learner.probeTotalSeconds + 1
        Task {
            let clock = ContinuousClock()
            do {
                try await clock.sleep(for: .seconds(Double(delay)))
            } catch {
                learnSheetLog.notice(
                    "probe.auto_restore.cancelled recovery=probe-cleanup-on-dismiss"
                )
                return
            }
            do {
                try await agentClient.setFanAuto(0)
            } catch {
                learnSheetLog.notice(
                    "probe.auto_restore_failed fan=0 error=\(error.localizedDescription, privacy: .public) recovery=next-agent-tick"
                )
            }
        }
    }

    var learnedSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                "Learned a curve from \(learner.samplesCollected) samples",
                systemImage: "checkmark.circle.fill"
            )
            .foregroundColor(Color(nsColor: .systemGreen))

            Text("Sampled \(Int(learner.minTempSampled))°C to \(Int(learner.maxTempSampled))°C")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(learner.learnedCurve.count) control points will replace your current curve.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider().padding(.vertical, 4)

            probeSection

            if let err = publishError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Color(nsColor: .systemOrange))
            }
        }
    }

    /// Second optional phase after sampling: briefly drive the fan at a
    /// high target to measure its true physical max. Result is written to
    /// the shared suite and picked up by overdriveTargetRPM automatically.
    @ViewBuilder
    private var probeSection: some View {
        if learner.isProbing {
            VStack(alignment: .leading, spacing: 6) {
                Text("Probing max RPM...")
                    .font(.callout.weight(.medium))
                ProgressView(
                    value: Double(learner.probeSecondsElapsed),
                    total: Double(learner.probeTotalSeconds))
                Text("\(Int(averageFanRPM)) RPM right now")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        } else if let result = learner.probeResult {
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    "Max sustained: \(Int(result.sustainedRPM)) RPM",
                    systemImage: "gauge.with.needle.fill"
                )
                .foregroundColor(Color(nsColor: .systemBlue))
                Text(
                    "Commanded \(Int(result.commandedRPM)) RPM across \(result.sampleCount) samples."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Text("Overdrive will now target this value.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(Color(nsColor: .systemOrange))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Probe max RPM (optional)")
                        .font(.callout.weight(.medium))
                    Text(
                        "Briefly drives fan 0 at a high target to measure its true mechanical limit. "
                            + "Loud for 15 seconds."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Button("Start Probe") { confirmProbe = true }
                        .controlSize(.small)
                }
            }
            .padding(8)
            .fancurveGlass(
                in: RoundedRectangle(cornerRadius: 6),
                fallbackFill: Color(nsColor: .systemOrange).opacity(0.08))
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            if !learner.learnedCurve.isEmpty {
                Button {
                    publishResults()
                } label: {
                    Label("Share Results", systemImage: "arrow.up.doc")
                }
                .controlSize(.regular)
                .disabled(learner.isProbing)
                .help("Opens a pre-filled pull request on GitHub with your sample data.")

                Button("Apply Curve") {
                    curveModel.replaceCurve(learner.learnedCurve)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else if learner.isSampling {
                Button("Stop and Use Partial Data") {
                    workload.stop()
                    learner.finish()
                }
            } else {
                Button("Start Sampling") {
                    priorFanControl = curveModel.isActive
                    curveModel.isActive = false
                    workload.start(cpu: runCPU, gpu: runGPU)
                    learner.start(sensorState: sensorState, totalSeconds: durationSeconds)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    var rangeLabel: String {
        guard learner.maxTempSampled > 0 else { return "none yet" }
        let lo = Int(learner.minTempSampled)
        let hi = Int(learner.maxTempSampled)
        return "\(lo) to \(hi)"
    }

    var averageFanRPM: Float {
        let fans = sensorState.fans
        guard !fans.isEmpty else { return 0 }
        return fans.reduce(0) { $0 + $1.actualRPM } / Float(fans.count)
    }

    @ViewBuilder
    func statCard(title: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded).weight(.medium))
            Text(sub)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
    }
}

extension LearnSheet {
    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Learn from System")
                .font(.title3.weight(.semibold))
            Text(
                "Samples temperature and fan speed for three minutes while macOS runs your machine in Auto. "
                    + "The result becomes your new curve."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    var sheetBody: some View {
        if !learner.learnedCurve.isEmpty {
            learnedSummary
        } else if learner.isSampling {
            samplingView
        } else {
            preSampleOptions
        }
    }

    var preSampleOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if sensorState.governingTemperature > 50 {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            "Your machine is already warm (\(Int(sensorState.governingTemperature))°C)."
                        )
                        .font(.callout.weight(.medium))
                        Text(
                            "Idle behavior below this temperature cannot be sampled. "
                                + "Wait for the machine to cool, or proceed and the curve will assume zero fan speed "
                                + "at lower temps."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Color(nsColor: .systemOrange))
                }
                .padding(10)
                .fancurveGlass(
                    in: RoundedRectangle(cornerRadius: 6),
                    fallbackFill: Color(nsColor: .systemOrange).opacity(0.10)
                )
            }

            Toggle("Stress the CPU during sampling", isOn: $runCPU)
            Toggle("Stress the GPU during sampling", isOn: $runGPU)

            Text(
                "Stressing both covers the whole thermal band quickly. "
                    + "Turning them off lets you load the machine with your own workload instead."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    var samplingView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView(
                value: Double(learner.secondsElapsed),
                total: Double(learner.totalSeconds)
            )

            HStack {
                statCard(
                    title: "Elapsed",
                    value: "\(learner.secondsElapsed)s",
                    sub: "of \(learner.totalSeconds)s"
                )
                statCard(
                    title: "Samples",
                    value: "\(learner.samplesCollected)",
                    sub: "one per second"
                )
                statCard(
                    title: "Temp range",
                    value: rangeLabel,
                    sub: "covered"
                )
            }

            HStack(spacing: 8) {
                Text("Current:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Int(sensorState.governingTemperature))°C")
                    .font(.system(.caption, design: .monospaced))
                Text("•")
                    .foregroundStyle(.secondary)
                Text("\(Int(averageFanRPM)) RPM avg")
                    .font(.system(.caption, design: .monospaced))
            }
        }
    }
}
