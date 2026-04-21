//
//  GlassModifiers.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import SwiftUI

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
    if #available(macOS 26.0, *) {
      self.glassEffect(in: shape)
    } else {
      self.background(shape.fill(fallbackFill))
    }
  }

  /// Glass-backed card for larger panels. Adds an outline stroke so the
  /// surface reads as a container on both versions.
  @ViewBuilder
  func fancurveGlassCard(cornerRadius: CGFloat = 12) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius)
    if #available(macOS 26.0, *) {
      self
        .glassEffect(in: shape)
        .overlay(shape.stroke(Color.primary.opacity(0.08)))
    } else {
      self
        .background(shape.fill(Color(nsColor: .textBackgroundColor)))
        .overlay(shape.stroke(Color.primary.opacity(0.08)))
    }
  }
}
