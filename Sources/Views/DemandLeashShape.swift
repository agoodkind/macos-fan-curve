//
//  DemandLeashShape.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026
//

import SwiftUI

typealias RuntimeMarkerLeashAnimatableData = AnimatablePair<
    AnimatablePair<CGFloat, CGFloat>,
    AnimatablePair<CGFloat, CGFloat>
>

struct DemandLeashShape: Shape {
    private var fanX: CGFloat
    private var fanY: CGFloat
    private var demandX: CGFloat
    private var demandY: CGFloat

    init(geometry: RuntimeMarkerOverlay.Geometry) {
        self.fanX = geometry.fanPosition.x
        self.fanY = geometry.fanPosition.y
        self.demandX = geometry.demandPosition.x
        self.demandY = geometry.demandPosition.y
    }

    var animatableData: RuntimeMarkerLeashAnimatableData {
        get {
            AnimatablePair(
                AnimatablePair(fanX, fanY),
                AnimatablePair(demandX, demandY)
            )
        }
        set {
            fanX = newValue.first.first
            fanY = newValue.first.second
            demandX = newValue.second.first
            demandY = newValue.second.second
        }
    }

    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: fanX, y: fanY))
        path.addLine(to: CGPoint(x: demandX, y: demandY))
        return path
    }
}
