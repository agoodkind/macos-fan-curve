//
//  FanInfo.swift
//  SMCFan
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026, all rights reserved.
//

public struct FanInfo: Sendable {
  public let actualRPM: Float
  public let targetRPM: Float
  public let minRPM: Float
  public let maxRPM: Float
  public let manualMode: Bool

  public init(
    actualRPM: Float,
    targetRPM: Float,
    minRPM: Float,
    maxRPM: Float,
    manualMode: Bool
  ) {
    self.actualRPM = actualRPM
    self.targetRPM = targetRPM
    self.minRPM = minRPM
    self.maxRPM = maxRPM
    self.manualMode = manualMode
  }
}
