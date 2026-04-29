//
//  DashedLine.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026
//

import SwiftUI

/// A straight dashed line shape that fills its frame along the given axis.
/// Using a Shape instead of a `Path` literal lets the surrounding `.position`
/// modifier animate the line smoothly as the anchor point changes.
struct DashedLine: Shape {
    enum Axis { case horizontal, vertical }

    let axis: Axis

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch axis {
        case .horizontal:
            let y = rect.midY
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        case .vertical:
            let x = rect.midX
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        return path
    }
}
