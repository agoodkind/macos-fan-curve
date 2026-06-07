//
//  LoadAssistKind.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026, all rights reserved.
//

enum LoadAssistKind: String, CaseIterable, Codable, Sendable {
  case cpu
  case gpu

  var title: String {
    switch self {
    case .cpu: return L10n.tr("CPU Load Assist")
    case .gpu: return L10n.tr("GPU Load Assist")
    }
  }

  var shortTitle: String {
    switch self {
    case .cpu: return "CPU"
    case .gpu: return "GPU"
    }
  }

  var enabledKey: String {
    switch self {
    case .cpu: return SharedConfigKeys.cpuLoadAssistEnabled
    case .gpu: return SharedConfigKeys.gpuLoadAssistEnabled
    }
  }

  var curvePointsKey: String {
    switch self {
    case .cpu: return SharedConfigKeys.cpuLoadAssistCurvePoints
    case .gpu: return SharedConfigKeys.gpuLoadAssistCurvePoints
    }
  }

  var legacyThresholdKey: String {
    switch self {
    case .cpu: return SharedConfigKeys.loadFloorThreshold
    case .gpu: return SharedConfigKeys.gpuLoadFloorThreshold
    }
  }
}
