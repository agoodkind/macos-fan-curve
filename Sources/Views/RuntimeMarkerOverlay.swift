//
//  RuntimeMarkerOverlay.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-30.
//  Copyright © 2026
//

import SwiftUI

/// Draws the live runtime markers as one shared surface so the dots, guides,
/// and leash all read from the same geometry object and animation transaction.
struct RuntimeMarkerOverlay: View {
    struct Geometry: Equatable {
        let size: CGSize
        let committedPosition: CGPoint
        let demandPosition: CGPoint
        let zeroY: CGFloat
        let plotLeft: CGFloat
    }

    let geometry: Geometry

    var body: some View {
        ZStack(alignment: .topLeading) {
            RuntimeMarkerGuidesShape(geometry: geometry)
                .stroke(
                    Color(nsColor: .systemOrange).opacity(0.25),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )

            RuntimeMarkerLeashShape(geometry: geometry)
                .stroke(
                    Color(nsColor: .systemOrange).opacity(0.24),
                    style: StrokeStyle(lineWidth: 1, dash: [2, 3])
                )

            Circle()
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                .overlay(
                    Circle().stroke(Color(nsColor: .systemOrange).opacity(0.58), lineWidth: 1.4)
                )
                .frame(width: 9, height: 9)
                .shadow(color: Color(nsColor: .systemOrange).opacity(0.18), radius: 2)
                .position(geometry.demandPosition)

            Circle()
                .fill(Color(nsColor: .systemOrange))
                .frame(width: 10, height: 10)
                .shadow(color: Color(nsColor: .systemOrange).opacity(0.5), radius: 6)
                .position(geometry.committedPosition)
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

private struct RuntimeMarkerGuidesShape: Shape {
    private var committedX: CGFloat
    private var committedY: CGFloat
    private var zeroY: CGFloat
    private var plotLeft: CGFloat

    init(geometry: RuntimeMarkerOverlay.Geometry) {
        self.committedX = geometry.committedPosition.x
        self.committedY = geometry.committedPosition.y
        self.zeroY = geometry.zeroY
        self.plotLeft = geometry.plotLeft
    }

    var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<CGFloat, CGFloat>
    > {
        get {
            AnimatablePair(
                AnimatablePair(committedX, committedY),
                AnimatablePair(zeroY, plotLeft)
            )
        }
        set {
            committedX = newValue.first.first
            committedY = newValue.first.second
            zeroY = newValue.second.first
            plotLeft = newValue.second.second
        }
    }

    func path(in _: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: committedX, y: committedY))
        path.addLine(to: CGPoint(x: committedX, y: zeroY))

        path.move(to: CGPoint(x: plotLeft, y: committedY))
        path.addLine(to: CGPoint(x: committedX, y: committedY))

        return path
    }
}

private struct RuntimeMarkerLeashShape: Shape {
    private var demandX: CGFloat
    private var demandY: CGFloat
    private var committedX: CGFloat
    private var committedY: CGFloat

    init(geometry: RuntimeMarkerOverlay.Geometry) {
        self.demandX = geometry.demandPosition.x
        self.demandY = geometry.demandPosition.y
        self.committedX = geometry.committedPosition.x
        self.committedY = geometry.committedPosition.y
    }

    var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<CGFloat, CGFloat>
    > {
        get {
            AnimatablePair(
                AnimatablePair(demandX, demandY),
                AnimatablePair(committedX, committedY)
            )
        }
        set {
            demandX = newValue.first.first
            demandY = newValue.first.second
            committedX = newValue.second.first
            committedY = newValue.second.second
        }
    }

    func path(in _: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: demandX, y: demandY))
        path.addLine(to: CGPoint(x: committedX, y: committedY))
        return path
    }
}
