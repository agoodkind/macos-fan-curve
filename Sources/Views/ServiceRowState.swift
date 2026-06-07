//
//  ServiceRowState.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026, all rights reserved.
//

import SwiftUI

enum ServiceRowState {
  case degraded
  case healthy
  case inactive

  var color: Color {
    switch self {
    case .healthy: return Color(nsColor: .systemGreen)
    case .degraded: return Color(nsColor: .systemOrange)
    case .inactive: return Color(nsColor: .systemGray)
    }
  }
}
