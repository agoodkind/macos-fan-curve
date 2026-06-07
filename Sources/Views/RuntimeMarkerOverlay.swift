//
//  RuntimeMarkerOverlay.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-30.
//  Copyright © 2026, all rights reserved.
//

import SwiftUI

// MARK: - Constants

private enum Mark {
  // Fan Now marker (filled orange dot)
  static let fanDiameter: CGFloat = 10
  static let fanShadowOpacity: Double = 0.5
  static let fanShadowRadius: CGFloat = 6

  // Thermal Demand marker (hollow orange dot)
  static let demandDiameter: CGFloat = 9
  static let demandFillOpacity: Double = 0.96
  static let demandStrokeOpacity: Double = 0.58
  static let demandStrokeWidth: CGFloat = 1.4
  static let demandShadowOpacity: Double = 0.18
  static let demandShadowRadius: CGFloat = 2

  // Fan Now crosshair guide line styling
  static let guidesOpacity: Double = 0.25
  static let guidesDashOn: CGFloat = 4
  static let guidesDashOff: CGFloat = 4

  // Demand leash line styling
  static let leashOpacity: Double = 0.24
  static let leashDashOn: CGFloat = 2
  static let leashDashOff: CGFloat = 3
}

/// Draws the live runtime markers as one shared surface so the dots, guides,
/// and relationship leash all read from the same geometry object and animation transaction.
struct RuntimeMarkerOverlay: View {
  struct Geometry: Equatable {
    let size: CGSize
    let fanPosition: CGPoint
    let demandPosition: CGPoint
    let zeroY: CGFloat
    let plotLeft: CGFloat
  }

  let geometry: Geometry

  var body: some View {
    ZStack(alignment: .topLeading) {
      FanNowGuidesShape(geometry: geometry)
        .stroke(
          Color(nsColor: .systemOrange).opacity(Mark.guidesOpacity),
          style: StrokeStyle(
            lineWidth: 1,
            dash: [Mark.guidesDashOn, Mark.guidesDashOff])
        )

      DemandLeashShape(geometry: geometry)
        .stroke(
          Color(nsColor: .systemOrange).opacity(Mark.leashOpacity),
          style: StrokeStyle(
            lineWidth: 1,
            dash: [Mark.leashDashOn, Mark.leashDashOff])
        )

      Circle()
        .fill(Color(nsColor: .windowBackgroundColor).opacity(Mark.demandFillOpacity))
        .overlay(
          Circle().stroke(
            Color(nsColor: .systemOrange).opacity(Mark.demandStrokeOpacity),
            lineWidth: Mark.demandStrokeWidth)
        )
        .frame(width: Mark.demandDiameter, height: Mark.demandDiameter)
        .shadow(
          color: Color(nsColor: .systemOrange).opacity(Mark.demandShadowOpacity),
          radius: Mark.demandShadowRadius
        )
        .position(geometry.demandPosition)

      Circle()
        .fill(Color(nsColor: .systemOrange))
        .frame(width: Mark.fanDiameter, height: Mark.fanDiameter)
        .shadow(
          color: Color(nsColor: .systemOrange).opacity(Mark.fanShadowOpacity),
          radius: Mark.fanShadowRadius
        )
        .position(geometry.fanPosition)
    }
    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
    .allowsHitTesting(false)
  }
}
