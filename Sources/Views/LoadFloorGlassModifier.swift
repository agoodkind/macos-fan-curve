//
//  LoadFloorGlassModifier.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-08.
//  Copyright © 2026
//

import SwiftUI

struct LoadFloorGlassModifier: ViewModifier {
    let color: Color
    let active: Bool

    func body(content: Content) -> some View {
        content
            .background(Capsule().fill(color.opacity(active ? 0.18 : 0.08)))
            .overlay(
                Capsule().stroke(color.opacity(active ? 0.7 : 0.4), lineWidth: 1.0)
            )
    }
}
