//
//  AgentController.swift
//  FanCurveAgent
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import Foundation
import SMCFanKit

/// Runs the curve-application loop in the background agent process.
/// Reads curve config from the shared UserDefaults suite every tick and
/// applies it via the privileged helper over XPC.
final class AgentController: @unchecked Sendable {
  private let xpcClient = XPCClient()
  private let sharedConfig = SharedConfig()
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
    Log.info("Agent starting (poll interval \(pollInterval)s)")
    timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
      Task { await self?.tick() }
    }
    Task { await tick() }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    sharedConfig.clearAgentStatus()
    xpcClient.shutdown()
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
      Log.info("Agent: all fans reset to auto on exit")
    } catch {
      Log.debug("Agent: reset on exit failed: \(error)")
    }
  }

  private func tick() async {
    let active = sharedConfig.loadIsActive()

    do {
      // Always read fans + temps so we know the fan count and governing temp.
      let result = try await xpcClient.readAndApply(
        fanCount: cachedFanCount,
        tempKeys: active ? tempKeys : [],
        setFans: nil,
        autoFans: nil
      )
      cachedFanCount = UInt(result.fans.count)

      // Publish health info
      sharedConfig.writeAgentStatus(pid: ProcessInfo.processInfo.processIdentifier, lastTick: Date())

      // On transition active -> inactive (or first tick when inactive), reset fans to auto.
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
          Log.info("Agent: curveActive=false, reset fans to auto")
        }
        return
      }
      guard !result.fans.isEmpty else { return }

      // Governing temperature = max CPU core
      var maxCPUTemp: Double = 0
      for (key, value) in result.temps where cpuTempKeys.contains(key) {
        maxCPUTemp = max(maxCPUTemp, Double(value))
      }
      guard maxCPUTemp > 0 else { return }

      // Evaluate curve
      let points = sharedConfig.loadCurve()
      let mode = sharedConfig.loadInterpolationMode()
      let percent = CurveInterpolation.evaluate(at: maxCPUTemp, points: points, mode: mode)

      Log.debug("Agent tick: \(Int(maxCPUTemp))C -> \(Int(percent * 100))%")

      // Derive per-fan commands
      var setFans: [(index: UInt, rpm: Float)]?
      var autoFans: [UInt]?
      if percent <= 0 {
        autoFans = Array(0..<UInt(result.fans.count))
      } else {
        setFans = result.fans.enumerated().map { (i, fan) in
          let rpm = fan.minRPM + Float(percent) * (fan.maxRPM - fan.minRPM)
          return (index: UInt(i), rpm: rpm)
        }
      }

      _ = try await xpcClient.readAndApply(
        fanCount: 0,
        tempKeys: [],
        setFans: setFans,
        autoFans: autoFans
      )
    } catch {
      Log.debug("Agent tick failed: \(error)")
    }
  }
}
