//
//  FanNowGuidesShape.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026, all rights reserved.
//

import SwiftUI

typealias RuntimeMarkerGuideAnimatableData = AnimatablePair<
  AnimatablePair<CGFloat, CGFloat>,
  AnimatablePair<CGFloat, CGFloat>
>

struct FanNowGuidesShape: Shape {
  private var fanX: CGFloat
  private var fanY: CGFloat
  private var zeroY: CGFloat
  private var plotLeft: CGFloat

  init(geometry: RuntimeMarkerOverlay.Geometry) {
    self.fanX = geometry.fanPosition.x
    self.fanY = geometry.fanPosition.y
    self.zeroY = geometry.zeroY
    self.plotLeft = geometry.plotLeft
  }

  var animatableData: RuntimeMarkerGuideAnimatableData {
    get {
      AnimatablePair(
        AnimatablePair(fanX, fanY),
        AnimatablePair(zeroY, plotLeft)
      )
    }
    set {
      fanX = newValue.first.first
      fanY = newValue.first.second
      zeroY = newValue.second.first
      plotLeft = newValue.second.second
    }
  }

  func path(in _: CGRect) -> Path {
    var path = Path()

    path.move(to: CGPoint(x: fanX, y: fanY))
    path.addLine(to: CGPoint(x: fanX, y: zeroY))

    path.move(to: CGPoint(x: plotLeft, y: fanY))
    path.addLine(to: CGPoint(x: fanX, y: fanY))

    return path
  }
}
