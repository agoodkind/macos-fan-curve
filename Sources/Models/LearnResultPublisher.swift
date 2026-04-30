//
//  LearnResultPublisher.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import AppKit
import AppLog
import Foundation

private let learnResultPublisherLog = AppLog.make(category: "LearnResultPublisher")

/// Opens a pre-filled pull request (actually a "new issue" URL in the
/// repository's compare flow) carrying the learned curve and probe
/// metadata. The exact payload format is intentionally simple for now.
/// The maintainer can evolve this into a proper data file once the
/// community starts submitting results.
enum LearnResultPublisher {
    private static let repository = "agoodkind/macos-fan-curve"

    static func publish(
        curve: [CurvePoint],
        minTemp: Double,
        maxTemp: Double,
        sampleCount: Int,
        probe: ProbeResult?
    ) throws {
        let body = buildBody(
            curve: curve,
            minTemp: minTemp,
            maxTemp: maxTemp,
            sampleCount: sampleCount,
            probe: probe)
        let title = "Learn results from \(hardwareModel())"

        guard var components = URLComponents(string: "https://github.com/\(repository)/issues/new") else {
            throw PublishError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "labels", value: "learn-curve"),
            URLQueryItem(name: "body", value: body),
        ]

        guard let url = components.url else {
            throw PublishError.invalidURL
        }
        learnResultPublisherLog.notice("learn.publish.open_url destination=github-issue")
        NSWorkspace.shared.open(url)
    }

    private static func buildBody(
        curve: [CurvePoint],
        minTemp: Double,
        maxTemp: Double,
        sampleCount: Int,
        probe: ProbeResult?
    ) -> String {
        var lines: [String] = []
        lines.append("## Machine")
        lines.append("")
        lines.append("- Model: \(hardwareModel())")
        lines.append("- macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("")
        lines.append("## Sampling")
        lines.append("")
        lines.append("- Temperature range: \(Int(minTemp))°C to \(Int(maxTemp))°C")
        lines.append("- Samples collected: \(sampleCount)")
        lines.append("")
        lines.append("## Curve")
        lines.append("")
        lines.append("| Temp (°C) | Fan % |")
        lines.append("|---:|---:|")
        for point in curve {
            lines.append(
                String(
                    format: "| %d | %.0f |",
                    Int(point.temperature),
                    point.fanPercent * 100))
        }
        lines.append("")
        if let probe {
            lines.append("## Max RPM probe")
            lines.append("")
            lines.append("- Fan index: \(probe.fanIndex)")
            lines.append("- Commanded: \(Int(probe.commandedRPM)) RPM")
            lines.append("- Sustained: \(Int(probe.sustainedRPM)) RPM")
            lines.append("- Samples: \(probe.sampleCount)")
            lines.append("")
        }
        lines.append("## Raw JSON")
        lines.append("")
        lines.append("```json")
        lines.append(
            jsonPayload(
                curve: curve,
                minTemp: minTemp,
                maxTemp: maxTemp,
                sampleCount: sampleCount,
                probe: probe))
        lines.append("```")
        return lines.joined(separator: "\n")
    }

    private static func jsonPayload(
        curve: [CurvePoint],
        minTemp: Double,
        maxTemp: Double,
        sampleCount: Int,
        probe: ProbeResult?
    ) -> String {
        var dict: [String: Any] = [
            "model": hardwareModel(),
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "samples": sampleCount,
            "minTemp": minTemp,
            "maxTemp": maxTemp,
            "curve": curve.map { ["t": $0.temperature, "p": $0.fanPercent] },
        ]
        if let probe {
            dict["probe"] = [
                "fan": probe.fanIndex,
                "commanded": probe.commandedRPM,
                "sustained": probe.sustainedRPM,
                "samples": probe.sampleCount,
            ]
        }
        let data = try? JSONSerialization.data(
            withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        return data.flatMap { String(bytes: $0, encoding: .utf8) } ?? "{}"
    }

    /// Reads hw.model via sysctl. Returns something like "Mac15,6" so the
    /// maintainer can group submissions by hardware revision.
    private static func hardwareModel() -> String {
        var size: size_t = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
            return "Unknown Mac"
        }
        var model = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &model, &size, nil, 0) == 0 else {
            return "Unknown Mac"
        }
        let bytes = model.prefix { $0 != 0 }.map(UInt8.init(bitPattern:))
        return String(bytes: bytes, encoding: .utf8) ?? "Unknown Mac"
    }

    enum PublishError: LocalizedError {
        case invalidURL

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid GitHub URL"
            }
        }
    }
}
