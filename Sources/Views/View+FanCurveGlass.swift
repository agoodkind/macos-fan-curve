//
//  View+FanCurveGlass.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026, all rights reserved.
//

import SwiftUI

private enum FanCurveGlassConstants {
    static let cardCornerRadius: CGFloat = 12
    static let outlineStrokeOpacity: Double = 0.08
    static let pillStrokeOpacity: Double = 0.08
    static let pillStrokeLineWidth: CGFloat = 0.5
}

/// Conditional Liquid Glass helpers. On macOS 26+ surfaces render with
/// .glassEffect, which gives the translucent layered look introduced
/// with Liquid Glass. On older macOS the fallback uses a solid fill so
/// the UI stays readable and keeps the same shape.
extension View {
    /// Applies Liquid Glass to the receiver's background when available.
    /// Falls back to a solid fill otherwise. Both paths respect the same
    /// shape so layout does not jump between versions.
    @ViewBuilder
    func fancurveGlass<S: Shape>(
        in shape: S,
        fallbackFill: Color = Color(nsColor: .windowBackgroundColor)
    ) -> some View {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                self.glassEffect(in: shape)
            } else {
                self.background(shape.fill(fallbackFill))
            }
        #else
            self.background(shape.fill(fallbackFill))
        #endif
    }

    /// Glass-backed card for larger panels. Adds an outline stroke so the
    /// surface reads as a container on both versions.
    @ViewBuilder
    func fancurveGlassCard(
        cornerRadius: CGFloat = FanCurveGlassConstants.cardCornerRadius
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                self
                    .glassEffect(in: shape)
                    .overlay(
                        shape.stroke(
                            Color.primary.opacity(FanCurveGlassConstants.outlineStrokeOpacity)))
            } else {
                self
                    .background(shape.fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(
                        shape.stroke(
                            Color.primary.opacity(FanCurveGlassConstants.outlineStrokeOpacity)))
            }
        #else
            self
                .background(shape.fill(Color(nsColor: .textBackgroundColor)))
                .overlay(
                    shape.stroke(Color.primary.opacity(FanCurveGlassConstants.outlineStrokeOpacity))
                )
        #endif
    }

    @ViewBuilder
    func fancurveGlassPill<S: Shape>(
        in shape: S,
        fallbackFill: Color = Color(nsColor: .windowBackgroundColor),
        stroke: Color = Color.primary.opacity(FanCurveGlassConstants.pillStrokeOpacity),
        lineWidth: CGFloat = FanCurveGlassConstants.pillStrokeLineWidth
    ) -> some View {
        self
            .fancurveGlass(in: shape, fallbackFill: fallbackFill)
            .overlay(shape.stroke(stroke, lineWidth: lineWidth))
    }
}
