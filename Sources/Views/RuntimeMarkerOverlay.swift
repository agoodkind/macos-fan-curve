//
//  RuntimeMarkerOverlay.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-30.
//  Copyright © 2026
//

import SwiftUI

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
                    Color(nsColor: .systemOrange).opacity(0.25),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )

            DemandLeashShape(geometry: geometry)
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
                .position(geometry.fanPosition)
        }
        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

private struct FanNowGuidesShape: Shape {
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

    var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<CGFloat, CGFloat>
    > {
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

private struct DemandLeashShape: Shape {
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

    var animatableData: AnimatablePair<
        AnimatablePair<CGFloat, CGFloat>,
        AnimatablePair<CGFloat, CGFloat>
    > {
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
