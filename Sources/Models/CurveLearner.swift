//
//  CurveLearner.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import AppLog
import Combine
import Foundation
import os.signpost

private let log = AppLog.make(category: "CurveLearner")
private let signposter = AppLog.signposter(category: "CurveLearner")

/// Result of a max-RPM probe. Records the highest actual RPM the fan
/// sustained while we commanded a very high target, and how confident
/// we are that the reading represents a true plateau.
struct ProbeResult {
    let fanIndex: UInt
    let commandedRPM: Float
    let sustainedRPM: Float
    let sampleCount: Int
}

/// Samples the current thermal response and fits a curve that mimics it.
/// The caller is expected to disable Fan Control while sampling so the
/// Agent does not override the firmware's Auto behavior.
@MainActor
final class CurveLearner: ObservableObject {
    @Published var isSampling = false
    @Published var samplesCollected = 0
    @Published var secondsElapsed = 0
    @Published var totalSeconds = 180
    @Published var minTempSampled: Double = .infinity
    @Published var maxTempSampled: Double = 0
    @Published var learnedCurve: [CurvePoint] = []

    @Published var isProbing = false
    @Published var probeSecondsElapsed = 0
    @Published var probeTotalSeconds = 15
    @Published var probeResult: ProbeResult?

    private var samples: [(temp: Double, percent: Double)] = []
    private var probeSamples: [Float] = []
    private var timer: Timer?
    private var probeTimer: Timer?
    private var sensorState: SensorState?
    private var sweepSignpostState: OSSignpostIntervalState?

    func start(sensorState: SensorState, totalSeconds: Int = 180) {
        if isSampling { return }
        reset()
        self.sensorState = sensorState
        self.totalSeconds = totalSeconds
        isSampling = true
        sweepSignpostState = signposter.beginInterval("learn.sweep")

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        isSampling = false
        samples.removeAll()
        if let state = sweepSignpostState {
            signposter.endInterval("learn.sweep", state)
            sweepSignpostState = nil
        }
    }

    func finish() {
        timer?.invalidate()
        timer = nil
        isSampling = false
        let curve = fitCurve()
        learnedCurve = curve
        persistRun(curve: curve)
        if let state = sweepSignpostState {
            signposter.endInterval("learn.sweep", state)
            sweepSignpostState = nil
        }
    }

    /// Writes the completed sweep to ~/Library/Application Support/io.goodkind.fan/learn-runs/<ISO8601>.json
    /// so LearnResultPublisher (and a future history view) can read it
    /// after an agent restart. The directory is created with 0o700 the
    /// first time a run is persisted.
    private func persistRun(curve: [CurvePoint]) {
        struct Payload: Codable {
            let timestamp: Date
            let minTemp: Double
            let maxTemp: Double
            let sampleCount: Int
            let curve: [CurvePoint]
            let probeFanIndex: UInt?
            let probeCommandedRPM: Float?
            let probeSustainedRPM: Float?
            let probeSampleCount: Int?
        }
        let payload = Payload(
            timestamp: Date(),
            minTemp: minTempSampled.isFinite ? minTempSampled : 0,
            maxTemp: maxTempSampled,
            sampleCount: samplesCollected,
            curve: curve,
            probeFanIndex: probeResult?.fanIndex,
            probeCommandedRPM: probeResult?.commandedRPM,
            probeSustainedRPM: probeResult?.sustainedRPM,
            probeSampleCount: probeResult?.sampleCount)

        let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir =
            support
            .appendingPathComponent("io.goodkind.fan", isDirectory: true)
            .appendingPathComponent("learn-runs", isDirectory: true)
        let fm = FileManager.default
        do {
            try fm.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        } catch {
            log.error(
                "learn.dir.failed path=\(dir.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: payload.timestamp).replacingOccurrences(
            of: ":", with: "-")
        let path = dir.appendingPathComponent("\(stamp).json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(payload)
            try data.write(to: path, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
            log.info("artifact.written path=\(path.path, privacy: .public) kind=learn-run")
        } catch {
            log.error("learn.write.failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    func reset() {
        samples.removeAll()
        samplesCollected = 0
        secondsElapsed = 0
        minTempSampled = .infinity
        maxTempSampled = 0
        learnedCurve = []
    }

    private func tick() {
        guard let sensorState else { return }
        let temp = sensorState.governingTemperature
        let fans = sensorState.fans
        guard temp > 0, !fans.isEmpty else {
            secondsElapsed += 1
            return
        }

        // Average percent across fans. Zero RPM maps to zero.
        var acc: Double = 0
        var count = 0
        for fan in fans where fan.maxRPM > fan.minRPM {
            let raw = Double((fan.actualRPM - fan.minRPM) / (fan.maxRPM - fan.minRPM))
            acc += max(0, min(1, raw))
            count += 1
        }
        guard count > 0 else {
            secondsElapsed += 1
            return
        }
        let percent = acc / Double(count)

        samples.append((temp, percent))
        samplesCollected = samples.count
        minTempSampled = min(minTempSampled, temp)
        maxTempSampled = max(maxTempSampled, temp)

        secondsElapsed += 1
        if secondsElapsed >= totalSeconds { finish() }
    }

    /// Bin samples by 5 degree buckets. Take the median percent in each bucket.
    /// Enforce monotonic non-decreasing so later buckets do not drop below
    /// earlier ones. Interpolate across empty buckets from their neighbors.
    private func fitCurve() -> [CurvePoint] {
        let bucketSize: Double = 5
        let lower: Double = 30
        let upper: Double = 100

        var bucketValues: [Double: [Double]] = [:]
        for sample in samples {
            let centerTemp = (sample.temp / bucketSize).rounded() * bucketSize
            guard centerTemp >= lower, centerTemp <= upper else { continue }
            bucketValues[centerTemp, default: []].append(sample.percent)
        }

        let temps = stride(from: lower, through: upper, by: bucketSize).map { Double($0) }
        let bucketMedian = medianPercentByTemperature(
            temperatures: temps,
            bucketValues: bucketValues
        )

        // If we have nothing, bail with the built-in default.
        guard !bucketMedian.isEmpty else {
            return FanCurveModel.defaultCurve
        }

        // Fill empty buckets by interpolating between nearest known neighbors.
        var filled: [(Double, Double)] = []
        let known = temps.filter { bucketMedian[$0] != nil }
        for temp in temps {
            if let value = bucketMedian[temp] {
                filled.append((temp, value))
                continue
            }
            guard
                let interpolatedValue = interpolatedBucketValue(
                    at: temp,
                    knownTemperatures: known,
                    bucketMedian: bucketMedian
                )
            else { continue }
            filled.append((temp, interpolatedValue))
        }

        // Enforce monotonic non-decreasing and clamp to 0 to 1.
        var lastValue: Double = 0
        let monotone = filled.map { sample -> (Double, Double) in
            let clamped = max(0, min(1, sample.1))
            let next = max(lastValue, clamped)
            lastValue = next
            return (sample.0, next)
        }

        return monotone.map { CurvePoint(temperature: $0.0, fanPercent: $0.1) }
    }

    private func medianPercentByTemperature(
        temperatures: [Double],
        bucketValues: [Double: [Double]]
    ) -> [Double: Double] {
        var bucketMedian: [Double: Double] = [:]
        for temp in temperatures {
            guard let values = bucketValues[temp], values.count >= 3 else {
                continue
            }
            let sorted = values.sorted()
            bucketMedian[temp] = sorted[sorted.count / 2]
        }
        return bucketMedian
    }

    private func interpolatedBucketValue(
        at temperature: Double,
        knownTemperatures: [Double],
        bucketMedian: [Double: Double]
    ) -> Double? {
        let previousTemperature = knownTemperatures.last { $0 < temperature }
        let nextTemperature = knownTemperatures.first { $0 > temperature }
        if let previousTemperature, let nextTemperature {
            guard
                let previousValue = bucketMedian[previousTemperature],
                let nextValue = bucketMedian[nextTemperature]
            else {
                return nil
            }
            let fraction =
                (temperature - previousTemperature) / (nextTemperature - previousTemperature)
            return previousValue + fraction * (nextValue - previousValue)
        }
        if let previousTemperature {
            return bucketMedian[previousTemperature]
        }
        if nextTemperature != nil {
            return 0
        }
        return nil
    }

    // MARK: - Max RPM Probe

    // Command the fan to a very high target and record the actual RPM it
    // reaches. The highest RPM the fan sustains is its true physical cap.
    // The caller is responsible for restoring the fan after the probe completes or fails.
    func startProbe(
        fanIndex: UInt,
        sensorState: SensorState,
        writeTarget: @escaping (UInt, Float) async throws -> Void,
        commandedRPM: Float = 15_000,
        seconds: Int = 15
    ) {
        if isProbing { return }
        isProbing = true
        probeSecondsElapsed = 0
        probeTotalSeconds = seconds
        probeSamples.removeAll()
        probeResult = nil
        self.sensorState = sensorState

        Task {
            do {
                try await writeTarget(fanIndex, commandedRPM)
            } catch {
                log.error(
                    "probe.start.failed fan=\(fanIndex, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=finish-probe"
                )
                await MainActor.run {
                    self.finishProbe(commandedRPM: commandedRPM, fanIndex: fanIndex)
                }
            }
        }

        probeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.probeTick(fanIndex: fanIndex, commandedRPM: commandedRPM) }
        }
    }

    func cancelProbe() {
        probeTimer?.invalidate()
        probeTimer = nil
        isProbing = false
        probeSamples.removeAll()
    }

    private func probeTick(fanIndex: UInt, commandedRPM: Float) {
        guard let sensorState else { return }
        let target = sensorState.fans.first { $0.id == fanIndex }
        if let fan = target {
            probeSamples.append(fan.actualRPM)
        }
        probeSecondsElapsed += 1
        if probeSecondsElapsed >= probeTotalSeconds {
            finishProbe(commandedRPM: commandedRPM, fanIndex: fanIndex)
        }
    }

    private func finishProbe(commandedRPM: Float, fanIndex: UInt) {
        probeTimer?.invalidate()
        probeTimer = nil
        isProbing = false

        // Use the 90th percentile of the second half of samples as a robust
        // estimate of the sustained plateau. Ignores the initial ramp-up.
        let trimmed = Array(probeSamples.dropFirst(max(0, probeSamples.count / 2)))
        let sustained: Float
        if trimmed.isEmpty {
            sustained = 0
        } else {
            let sorted = trimmed.sorted()
            let idx = min(sorted.count - 1, Int(Double(sorted.count) * 0.9))
            sustained = sorted[idx]
        }

        probeResult = ProbeResult(
            fanIndex: fanIndex,
            commandedRPM: commandedRPM,
            sustainedRPM: sustained,
            sampleCount: probeSamples.count)

        if sustained > 0 {
            sharedDefaults().set(
                Double(sustained), forKey: SharedConfigKeys.overdriveTargetRPMMeasured)
        }
    }
}
