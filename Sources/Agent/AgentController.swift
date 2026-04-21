//
//  AgentController.swift
//  FanCurveAgent
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import AppLog
import Foundation
import SMCFanKit

private let log = AppLog.make(category: "AgentController")

/// Runs the curve application loop in the background agent process.
/// Reads curve config from the shared UserDefaults suite every tick and
/// applies it via the privileged helper over XPC.
final class AgentController: @unchecked Sendable {
    private let xpcClient = XPCClient()
    private let sharedConfig = SharedConfig()
    private let loadSampler = CPULoadSampler()
    private let eventWriter = EventArtifactWriter()
    private var timer: Timer?
    private var cachedFanCount: UInt = 2
    private var lastActive: Bool? = nil

    private let pollInterval: TimeInterval = 1.0

    private let tempKeys: [String] = SensorCatalog.keysForCurrentHardware()
        .filter { $0.type == .temperature }
        .map { $0.key }

    private let cpuTempKeys: Set<String> = Set(
        SensorCatalog.keysForCurrentHardware()
            .filter { $0.type == .temperature && $0.group == .cpu }
            .map { $0.key }
    )

    func start() {
        log.notice("agent.started pollInterval=\(pollInterval, privacy: .public)s")
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { await self?.tick() }
        }
        registerDarwinObserver()
        Task { await tick() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        unregisterDarwinObserver()
        sharedConfig.clearAgentStatus()
        xpcClient.shutdown()
        log.notice("agent.stopped")
    }

    private func registerDarwinObserver() {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let controller = Unmanaged<AgentController>
                    .fromOpaque(observer).takeUnretainedValue()
                Task { await controller.tick() }
            },
            SharedConfigPush.notificationName,
            nil,
            .deliverImmediately)
        log.info("agent.darwin.observer.registered name=\(SharedConfigPush.notificationNameString, privacy: .public)")
    }

    private func unregisterDarwinObserver() {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            observer)
    }

    /// Reset all fans to auto mode. Called on SIGTERM/SIGINT before exit.
    func resetAllFansToAuto() async {
        do {
            _ = try await xpcClient.readAndApply(
                fanCount: cachedFanCount,
                tempKeys: [],
                setFans: nil,
                autoFans: Array(0..<cachedFanCount)
            )
            log.notice("agent.fans.reset.auto")
        } catch {
            log.error("agent.fans.reset.failed error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func tick() async {
        let active = sharedConfig.loadIsActive()

        do {
            let result = try await xpcClient.readAndApply(
                fanCount: cachedFanCount,
                tempKeys: active ? tempKeys : [],
                setFans: nil,
                autoFans: nil
            )
            cachedFanCount = UInt(result.fans.count)

            sharedConfig.writeAgentStatus(pid: ProcessInfo.processInfo.processIdentifier, lastTick: Date())
            sharedConfig.writeAgentLastError(nil)

            let transitioned = (lastActive != active)
            lastActive = active
            if !active {
                if transitioned, !result.fans.isEmpty {
                    _ = try? await xpcClient.readAndApply(
                        fanCount: 0,
                        tempKeys: [],
                        setFans: nil,
                        autoFans: Array(0..<UInt(result.fans.count))
                    )
                    log.notice("agent.curve.deactivated fans=auto")
                }
                return
            }
            guard !result.fans.isEmpty else { return }

            var maxCPUTemp: Double = 0
            for (key, value) in result.temps where cpuTempKeys.contains(key) {
                maxCPUTemp = max(maxCPUTemp, Double(value))
            }
            guard maxCPUTemp > 0 else { return }

            loadSampler.sample()

            let boost = sharedConfig.loadBoostEnabled()
            var percent: Double
            if boost {
                percent = 1.0
            } else {
                let points = sharedConfig.loadCurve()
                let mode = sharedConfig.loadInterpolationMode()
                percent = CurveInterpolation.evaluate(at: maxCPUTemp, points: points, mode: mode)
            }

            var floorApplied = false
            if !boost, sharedConfig.loadLoadFloorEnabled() {
                let cpu = loadSampler.smoothed
                let gpu = readGPULoadPercent()
                let cpuFires = cpu >= sharedConfig.loadLoadFloorThreshold()
                let gpuFires = gpu >= sharedConfig.loadGpuLoadFloorThreshold()
                if cpuFires || gpuFires {
                    let floor = sharedConfig.loadLoadFloorPercent() / 100.0
                    if floor > percent {
                        percent = floor
                        floorApplied = true
                    }
                }
            }

            log.debug("agent.tick cpuTemp=\(Int(maxCPUTemp), privacy: .public)C load=\(Int(loadSampler.smoothed), privacy: .public)% target=\(Int(percent * 100), privacy: .public)% boost=\(boost, privacy: .public) floorApplied=\(floorApplied, privacy: .public)")

            var setFans: [(index: UInt, rpm: Float)] = []
            var autoFans: [UInt] = []
            for (i, fan) in result.fans.enumerated() {
                let command = fanCommandFor(percent: percent, minRPM: fan.minRPM, maxRPM: fan.maxRPM)
                switch command {
                case .setRPM(let rpm): setFans.append((index: UInt(i), rpm: rpm))
                case .auto: autoFans.append(UInt(i))
                }
            }

            _ = try await xpcClient.readAndApply(
                fanCount: 0,
                tempKeys: [],
                setFans: setFans.isEmpty ? nil : setFans,
                autoFans: autoFans.isEmpty ? nil : autoFans
            )

            eventWriter.append(
                kind: boost ? "boost" : (floorApplied ? "floor" : "curve"),
                fanRPM: result.fans.map { $0.actualRPM },
                tempC: maxCPUTemp,
                curvePoint: percent)
        } catch {
            log.error("agent.tick.failed error=\(error.localizedDescription, privacy: .public)")
            sharedConfig.writeAgentLastError("\(error)")
        }
    }
}
