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
