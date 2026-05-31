//
//  LoadFloorGlassModifier.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026, all rights reserved.
//

import SwiftUI

private enum LoadFloorGlassConstants {
    static let activeFillOpacity: Double = 0.18
    static let inactiveFillOpacity: Double = 0.08
    static let activeStrokeOpacity: Double = 0.7
    static let inactiveStrokeOpacity: Double = 0.4
    static let strokeLineWidth: CGFloat = 1.0
}

struct LoadFloorGlassModifier: ViewModifier {
    let color: Color
    let active: Bool

    func body(content: Content) -> some View {
        content
            .background(
                Capsule().fill(
                    color.opacity(
                        active
                            ? LoadFloorGlassConstants.activeFillOpacity
                            : LoadFloorGlassConstants.inactiveFillOpacity
                    )
                )
            )
            .overlay(
                Capsule().stroke(
                    color.opacity(
                        active
                            ? LoadFloorGlassConstants.activeStrokeOpacity
                            : LoadFloorGlassConstants.inactiveStrokeOpacity
                    ),
                    lineWidth: LoadFloorGlassConstants.strokeLineWidth
                )
            )
    }
}
