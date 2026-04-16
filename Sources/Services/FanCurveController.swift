//
//  FanCurveController.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

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

  init(xpcClient: XPCClient, curveModel: FanCurveModel, sensorState: SensorState) {
    self.xpcClient = xpcClient
    self.curveModel = curveModel
    self.sensorState = sensorState
  }

  func start() {
    guard !isRunning else { return }
    isRunning = true
    timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
      Task { await self?.tick() }
    }
    Log.info("Fan curve controller started (1s poll interval)")
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
        for fan in fans {
          let rpm = curveModel.rpmForFan(
            percent: percent, minRPM: fan.minRPM, maxRPM: fan.maxRPM)
          if percent <= 0 {
            try? await xpcClient.setFanAuto(UInt(fan.id))
          } else {
            try? await xpcClient.setFanRPM(UInt(fan.id), rpm: rpm)
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
