//
//  XPCClient+Batch.swift
//  FanCurveAgent
//
//  Created by Codex <noreply@openai.com> on 2026-08-13.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

private let xpcClientBatchLog = AppLog.make(category: "XPCClientBatch")

private struct IndexedFanBatch {
  let readings: [FanHardwareFanReading]
  let expectedFanCount: UInt
}

// MARK: - XPCClient

extension XPCClient {
  func readAndApply(
    fanCount: UInt,
    tempKeys: [String],
    setFans: [(index: UInt, rpm: Float)] = [],
    autoFans: [UInt] = [],
    priority: Int? = nil
  ) async -> FanHardwareBatchRead {
    let fanBatch = await readIndexedFans(fanCount: fanCount)
    let temperatures = await readTemperatures(tempKeys)
    await applyFanTargets(setFans, priority: priority)
    await applyAutomaticFans(autoFans, priority: priority)
    return FanHardwareBatchRead(
      indexedFans: fanBatch.readings,
      expectedFanCount: fanBatch.expectedFanCount,
      temps: temperatures
    )
  }

  private func readIndexedFans(fanCount: UInt) async -> IndexedFanBatch {
    var readings: [FanHardwareFanReading] = []
    var fanReadFailed = false
    for fanIndex in 0..<fanCount {
      do {
        let info = try await getFanInfo(fanIndex)
        readings.append(FanHardwareFanReading(index: fanIndex, info: info))
      } catch {
        fanReadFailed = true
        xpcClientBatchLog.notice(
          "xpc.batch.fan_read_failed fan=\(fanIndex, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=preserve-index-and-retry-next-tick"
        )
      }
    }
    let expectedFanCount = await refreshedFanCountAfterFailure(
      requestedFanCount: fanCount,
      fanReadFailed: fanReadFailed
    )
    return IndexedFanBatch(readings: readings, expectedFanCount: expectedFanCount)
  }

  private func refreshedFanCountAfterFailure(
    requestedFanCount: UInt,
    fanReadFailed: Bool
  ) async -> UInt {
    guard fanReadFailed else { return requestedFanCount }
    do {
      let fanCount = try await requireClient().getFanCount()
      markConnected()
      return fanCount
    } catch {
      xpcClientBatchLog.notice(
        "xpc.batch.fan_count_refresh_failed error=\(error.localizedDescription, privacy: .public) recovery=retain-requested-count"
      )
      return requestedFanCount
    }
  }

  private func applyFanTargets(
    _ targets: [(index: UInt, rpm: Float)],
    priority: Int?
  ) async {
    for target in targets {
      do {
        try await setFanRPM(target.index, rpm: target.rpm, priority: priority)
      } catch {
        xpcClientBatchLog.notice(
          "xpc.batch.fan_write_failed fan=\(target.index, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=continue-batch"
        )
      }
    }
  }

  private func applyAutomaticFans(_ fanIndices: [UInt], priority: Int?) async {
    for fanIndex in fanIndices {
      do {
        try await setFanAuto(fanIndex, priority: priority)
      } catch {
        xpcClientBatchLog.notice(
          "xpc.batch.auto_write_failed fan=\(fanIndex, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=continue-batch"
        )
      }
    }
  }
}
