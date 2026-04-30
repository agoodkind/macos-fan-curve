//
//  EventArtifactWriter.swift
//  FanCurveAgent
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-18.
//  Copyright © 2026
//

import AppLog
import Foundation

private let log = AppLog.make(category: "EventArtifactWriter")

/// Append-only NDJSON ring of agent tick events. Future GUI history view
/// reads this file directly. Two-file cap: when events.jsonl crosses the
/// 50 MB threshold it is renamed to events.1.jsonl (overwriting any prior
/// rotation) and a fresh events.jsonl is started.
///
/// Lives in ~/Library/Application Support/io.goodkind.fan/. The directory
/// is created with 0o700 so other users on the box cannot read tick data.
final class EventArtifactWriter: @unchecked Sendable {
    struct Event: Codable, Sendable {
        let schemaVersion: Int
        let ts: Date
        let kind: String
        let governingTempC: Double
        let rawTemperatureC: Double
        let fastTemperatureC: Double
        let slowTemperatureC: Double
        let cpuLoadPercent: Double
        let gpuLoadPercent: Double
        let effectiveCurvePercent: Double
        let rawBaselinePercent: Double
        let committedPercent: Double
        let bandIndex: Int
        let holdRemainingSeconds: Double
        let thermalDebt: Double
        let controllerMode: String
        let assistFloorPercent: Double?
        let activeAssistKinds: [String]
        let fanActualRPM: [Float]
        let fanTargetRPM: [Float]
        let fanMinRPM: [Float]
        let fanMaxRPM: [Float]
        let fanManualMode: [Bool]
    }

    struct AppendRequest: Sendable {
        let timestamp: Date
        let kind: String
        let governingTempC: Double
        let rawTemperatureC: Double
        let fastTemperatureC: Double
        let slowTemperatureC: Double
        let cpuLoadPercent: Double
        let gpuLoadPercent: Double
        let effectiveCurvePercent: Double
        let rawBaselinePercent: Double
        let committedPercent: Double
        let bandIndex: Int
        let holdRemainingSeconds: Double
        let thermalDebt: Double
        let controllerMode: String
        let assistFloorPercent: Double?
        let activeAssistKinds: [String]
        let fanActualRPM: [Float]
        let fanTargetRPM: [Float]
        let fanMinRPM: [Float]
        let fanMaxRPM: [Float]
        let fanManualMode: [Bool]
    }

    private let lock = NSLock()
    private let directory: URL
    private let activeJSON: URL
    private let rotatedJSON: URL
    private let activeCSV: URL
    private let rotatedCSV: URL
    private let rotateThreshold: Int = 50 * 1_024 * 1_024
    private let encoder: JSONEncoder
    private let csvHeader =
        [
            "ts",
            "kind",
            "governing_temp_c",
            "raw_temp_c",
            "fast_temp_c",
            "slow_temp_c",
            "cpu_load_percent",
            "gpu_load_percent",
            "effective_curve_percent",
            "raw_baseline_percent",
            "committed_percent",
            "band_index",
            "hold_remaining_seconds",
            "thermal_debt",
            "controller_mode",
            "assist_floor_percent",
            "active_assist_kinds",
            "fan_actual_rpm",
            "fan_target_rpm",
            "fan_min_rpm",
            "fan_max_rpm",
            "fan_manual_mode",
            "fan_avg_actual_rpm",
            "fan_avg_target_rpm",
        ].joined(separator: ",") + "\n"

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.directory = support.appendingPathComponent("io.goodkind.fan", isDirectory: true)
        self.activeJSON = directory.appendingPathComponent("events.jsonl")
        self.rotatedJSON = directory.appendingPathComponent("events.1.jsonl")
        self.activeCSV = directory.appendingPathComponent("events.csv")
        self.rotatedCSV = directory.appendingPathComponent("events.1.csv")

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        ensureDirectory()
    }

    func append(_ request: AppendRequest) {
        let event = Event(
            schemaVersion: 2,
            ts: request.timestamp,
            kind: request.kind,
            governingTempC: request.governingTempC,
            rawTemperatureC: request.rawTemperatureC,
            fastTemperatureC: request.fastTemperatureC,
            slowTemperatureC: request.slowTemperatureC,
            cpuLoadPercent: request.cpuLoadPercent,
            gpuLoadPercent: request.gpuLoadPercent,
            effectiveCurvePercent: request.effectiveCurvePercent,
            rawBaselinePercent: request.rawBaselinePercent,
            committedPercent: request.committedPercent,
            bandIndex: request.bandIndex,
            holdRemainingSeconds: request.holdRemainingSeconds,
            thermalDebt: request.thermalDebt,
            controllerMode: request.controllerMode,
            assistFloorPercent: request.assistFloorPercent,
            activeAssistKinds: request.activeAssistKinds,
            fanActualRPM: request.fanActualRPM,
            fanTargetRPM: request.fanTargetRPM,
            fanMinRPM: request.fanMinRPM,
            fanMaxRPM: request.fanMaxRPM,
            fanManualMode: request.fanManualMode
        )
        do {
            var jsonData = try encoder.encode(event)
            jsonData.append(0x0A)
            let csvData = Data(csvLine(for: event).utf8)

            lock.lock()
            defer { lock.unlock() }

            rotateIfNeededLocked()
            try writeLocked(jsonData, to: activeJSON, header: nil)
            try writeLocked(csvData, to: activeCSV, header: csvHeader)
            log.info("event.recorded kind=\(event.kind, privacy: .public)")
        } catch {
            log.error(
                "event.write.failed kind=\(event.kind, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func ensureDirectory() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
        } catch {
            log.error(
                "artifact.dir.failed path=\(directory.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func rotateIfNeededLocked() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: activeJSON.path)
        guard let size = attrs?[.size] as? Int, size >= rotateThreshold else { return }
        let fm = FileManager.default
        removeRotatedArtifactIfPresent(rotatedJSON)
        removeRotatedArtifactIfPresent(rotatedCSV)
        do {
            if fm.fileExists(atPath: activeJSON.path) {
                try fm.moveItem(at: activeJSON, to: rotatedJSON)
            }
            if fm.fileExists(atPath: activeCSV.path) {
                try fm.moveItem(at: activeCSV, to: rotatedCSV)
            }
            log.notice(
                "artifact.rotated from=\(activeJSON.lastPathComponent, privacy: .public) to=\(rotatedJSON.lastPathComponent, privacy: .public)"
            )
        } catch {
            log.error("artifact.rotate.failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func removeRotatedArtifactIfPresent(_ url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        do {
            try fm.removeItem(at: url)
        } catch {
            log.notice(
                "artifact.rotate.cleanup_failed path=\(url.lastPathComponent, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=overwrite-attempt"
            )
        }
    }

    private func writeLocked(_ data: Data, to url: URL, header: String?) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            var initial = Data()
            if let header {
                initial.append(Data(header.utf8))
            }
            initial.append(data)
            fm.createFile(atPath: url.path, contents: initial, attributes: [.posixPermissions: 0o600])
            log.info("artifact.written path=\(url.path, privacy: .public) kind=create")
            return
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    private func csvLine(for event: Event) -> String {
        let avgActual =
            event.fanActualRPM.isEmpty ? 0 : event.fanActualRPM.reduce(0, +) / Float(event.fanActualRPM.count)
        let avgTarget =
            event.fanTargetRPM.isEmpty ? 0 : event.fanTargetRPM.reduce(0, +) / Float(event.fanTargetRPM.count)
        let columns: [String] = [
            iso8601(event.ts),
            event.kind,
            decimal(event.governingTempC),
            decimal(event.rawTemperatureC),
            decimal(event.fastTemperatureC),
            decimal(event.slowTemperatureC),
            decimal(event.cpuLoadPercent),
            decimal(event.gpuLoadPercent),
            decimal(event.effectiveCurvePercent),
            decimal(event.rawBaselinePercent),
            decimal(event.committedPercent),
            String(event.bandIndex),
            decimal(event.holdRemainingSeconds),
            decimal(event.thermalDebt),
            event.controllerMode,
            event.assistFloorPercent.map(decimal) ?? "",
            event.activeAssistKinds.joined(separator: "|"),
            event.fanActualRPM.map(decimal).joined(separator: "|"),
            event.fanTargetRPM.map(decimal).joined(separator: "|"),
            event.fanMinRPM.map(decimal).joined(separator: "|"),
            event.fanMaxRPM.map(decimal).joined(separator: "|"),
            event.fanManualMode.map { $0 ? "1" : "0" }.joined(separator: "|"),
            decimal(avgActual),
            decimal(avgTarget),
        ]
        return columns.map(csvEscape).joined(separator: ",") + "\n"
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private func decimal<T: BinaryFloatingPoint>(_ value: T) -> String {
        String(Double(value))
    }

    private func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
