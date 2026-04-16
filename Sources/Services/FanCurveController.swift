//
//  FanCurveController.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import AppKit
import Foundation
import SMCFanKit

class FanCurveController: ObservableObject, @unchecked Sendable {
  private let xpcClient: XPCClient
  private let curveModel: FanCurveModel
  private let sensorState: SensorState
  private var timer: Timer?

  private let tempKeys = SensorCatalog.keysForCurrentHardware()
    .filter { $0.type == .temperature && $0.group == .cpu }

  @Published var isRunning = false
  private var isAppActive = true

  private var pollInterval: TimeInterval {
    isAppActive ? 0.5 : 2.0
  }

  init(xpcClient: XPCClient, curveModel: FanCurveModel, sensorState: SensorState) {
    self.xpcClient = xpcClient
    self.curveModel = curveModel
    self.sensorState = sensorState

    NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.isAppActive = true
      self?.rescheduleTimer()
    }
    NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.isAppActive = false
      self?.rescheduleTimer()
    }
  }

  func start() {
    guard !isRunning else { return }
    isRunning = true
    scheduleTimer()
    Log.info("Fan curve controller started (\(pollInterval)s poll interval)")
  }

  private func scheduleTimer() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
      Task { await self?.tick() }
    }
  }

  private func rescheduleTimer() {
    guard isRunning else { return }
    scheduleTimer()
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    isRunning = false

    Task {
      await resetAllFansToAuto()
    }
    Log.info("Fan curve controller stopped, fans reset to auto")
  }

  func resetFans() async {
    await resetAllFansToAuto()
    Log.info("Fans reset to auto (curve control disabled)")
  }

  private func tick() async {
    do {
      // Read fan info
      let fanCount = try await xpcClient.getFanCount()
      var fans: [FanReading] = []
      for i in 0..<fanCount {
        let info = try await xpcClient.getFanInfo(i)
        fans.append(FanReading(
          id: Int(i), actualRPM: info.actualRPM, targetRPM: info.targetRPM,
          minRPM: info.minRPM, maxRPM: info.maxRPM, manualMode: info.manualMode))
      }

      // Read temps
      var temps: [SensorReading] = []
      var maxCPUTemp: Double = 0
      for sensor in tempKeys {
        if let value = try? await xpcClient.readKey(sensor.key),
          value > 0, value < 150
        {
          temps.append(SensorReading(
            id: sensor.key, name: sensor.name,
            group: sensor.group.rawValue, value: Double(value)))
          if sensor.group == .cpu {
            maxCPUTemp = max(maxCPUTemp, Double(value))
          }
        }
      }

      // Also read system and GPU temps for display
      let allKeys = SensorCatalog.keysForCurrentHardware()
        .filter { $0.type == .temperature && $0.group != .cpu }
      for sensor in allKeys {
        if let value = try? await xpcClient.readKey(sensor.key),
          value > 0, value < 150
        {
          temps.append(SensorReading(
            id: sensor.key, name: sensor.name,
            group: sensor.group.rawValue, value: Double(value)))
        }
      }

      // Update state on main thread
      await MainActor.run {
        sensorState.fans = fans
        sensorState.temperatures = temps
        sensorState.governingTemperature = maxCPUTemp
        sensorState.lastUpdate = Date()
      }

      // Apply curve if active
      if curveModel.isActive, maxCPUTemp > 0 {
        let percent = curveModel.evaluate(at: maxCPUTemp)
        Log.debug("curve eval: temp=\(Int(maxCPUTemp))C percent=\(Int(percent * 100))%")
        for fan in fans {
          let rpm = curveModel.rpmForFan(
            percent: percent, minRPM: fan.minRPM, maxRPM: fan.maxRPM)
          if percent <= 0 {
            do {
              try await xpcClient.setFanAuto(UInt(fan.id))
              Log.debug("fan \(fan.id) set to auto (curve says 0%)")
            } catch {
              Log.debug("fan \(fan.id) setAuto failed: \(error)")
            }
          } else {
            do {
              try await xpcClient.setFanRPM(UInt(fan.id), rpm: rpm)
              Log.debug("fan \(fan.id) set to \(Int(rpm)) RPM (curve=\(Int(percent * 100))%)")
            } catch {
              Log.debug("fan \(fan.id) setRPM failed: \(error)")
            }
          }
        }
      }
    } catch {
      Log.debug("tick failed: \(error)")
    }
  }

  private func resetAllFansToAuto() async {
    do {
      let count = try await xpcClient.getFanCount()
      for i in 0..<count {
        try? await xpcClient.setFanAuto(i)
      }
    } catch {
      Log.debug("failed to reset fans to auto: \(error)")
    }
  }
}
