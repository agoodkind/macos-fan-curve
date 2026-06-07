//
//  FanCommand.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026, all rights reserved.
//

enum FanCommand: Sendable {
  case auto
  case setRPM(Float)
}
