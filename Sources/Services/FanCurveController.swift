//
//  FanCurveController.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//
//  Read-only sensor poller for the GUI. Polls the helper for fan and temp
//  readings and publishes to SensorState for the UI. Does NOT write fan
//  speeds. The FanCurveAgent LaunchAgent owns fan control.
//

import AppKit
import AppLog
import Foundation
import SMCFanKit

private let log = AppLog.make(category: "XPCClient")

final class FanCurveController: ObservableObject, @unchecked Sendable {
    private let xpcClient: XPCClient
    private let sensorState: SensorState
    private var timer: Timer?
    private var cachedFanCount: UInt = 2
    private var isAppActive = true

    private let tempKeys: [String] = SensorCatalog.keysForCurrentHardware()
        .filter { $0.type == .temperature }
        .map { $0.key }

    private let cpuTempKeys: Set<String> = Set(
        SensorCatalog.keysForCurrentHardware()
            .filter { $0.type == .temperature && $0.group == .cpu }
            .map { $0.key }
    )

    private let sensorLookup: [String: SensorKey] = {
        var lookup: [String: SensorKey] = [:]
        for s in SensorCatalog.keysForCurrentHardware() where s.type == .temperature {
            lookup[s.key] = s
        }
        return lookup
    }()

    private var pollInterval: TimeInterval { isAppActive ? 0.5 : 2.0 }

    init(xpcClient: XPCClient, sensorState: SensorState) {
        self.xpcClient = xpcClient
        self.sensorState = sensorState

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.isAppActive = true
            self?.reschedule()
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.isAppActive = false
            self?.reschedule()
        }
    }

    func start() {
        schedule()
        Task { await tick() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { await self?.tick() }
        }
    }

    private func reschedule() {
        guard timer != nil else { return }
        schedule()
    }

    private func tick() async {
        do {
            let result = try await xpcClient.readAndApply(
                fanCount: cachedFanCount,
                tempKeys: tempKeys,
                setFans: nil,
                autoFans: nil
            )
            cachedFanCount = UInt(result.fans.count)

            var fans: [FanReading] = []
            for (i, info) in result.fans.enumerated() {
                fans.append(FanReading(
                    id: i, actualRPM: info.actualRPM, targetRPM: info.targetRPM,
                    minRPM: info.minRPM, maxRPM: info.maxRPM, manualMode: info.manualMode))
            }

            var temps: [SensorReading] = []
            var maxCPUTemp: Double = 0
            for (key, value) in result.temps {
                let sensor = sensorLookup[key]
                temps.append(SensorReading(
                    id: key, name: sensor?.name ?? key,
                    group: sensor?.group.rawValue ?? "Unknown", value: Double(value)))
                if cpuTempKeys.contains(key) {
                    maxCPUTemp = max(maxCPUTemp, Double(value))
                }
            }

            await MainActor.run {
                sensorState.fans = fans
                sensorState.temperatures = temps
                sensorState.governingTemperature = maxCPUTemp
                sensorState.lastUpdate = Date()
            }
        } catch {
            log.debug("gui.tick.failed error=\(error.localizedDescription, privacy: .public)")
        }
    }
}
