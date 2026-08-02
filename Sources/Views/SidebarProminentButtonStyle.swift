//
//  SidebarProminentButtonStyle.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-08-01.
//  Copyright © 2026, all rights reserved.
//

import SwiftUI

private enum SidebarProminentButtonConstants {
  static let horizontalPadding: CGFloat = 14
  static let verticalPadding: CGFloat = 7

  // Fallback chrome for macOS versions without Liquid Glass.
  static let inactiveTintOpacity: Double = 0.12
  static let inactiveBorderOpacity: Double = 0.45
  static let borderLineWidth: CGFloat = 0.8
  static let hoverTintBoost: Double = 0.10
  static let pressedOpacity: Double = 0.82
  static let stateAnimationDuration: TimeInterval = 0.12
}

// MARK: - SidebarProminentButtonStyle

/// The sidebar's full-width action buttons: Boost, and the setup call to action.
///
/// On macOS 26 the button is Liquid Glass. `interactive()` is what gives it the
/// hover and press reactions the system gives its own buttons, so this style
/// does not track the pointer itself. Older macOS keeps the tinted capsule and
/// gets the same two states drawn by hand.
///
/// `tint` stays per-button rather than using `.glassProminent`, which would
/// force the accent color on Boost and lose its orange.
struct SidebarProminentButtonStyle: ButtonStyle {
  let tint: Color
  let isActive: Bool
  let isBusy: Bool

  func makeBody(configuration: Configuration) -> some View {
    SidebarProminentButtonBody(
      configuration: configuration,
      tint: tint,
      isActive: isActive,
      isBusy: isBusy
    )
  }
}

// MARK: - SidebarProminentButtonBody

/// A view rather than inline body content, because the pre-macOS 26 fallback
/// needs `@State` to track hover and a `ButtonStyle` is a struct.
private struct SidebarProminentButtonBody: View {
  let configuration: ButtonStyleConfiguration
  let tint: Color
  let isActive: Bool
  let isBusy: Bool

  @State private var isHovering = false

  var body: some View {
    label
      .frame(maxWidth: .infinity)
      .background { background }
      .onHover { hovering in isHovering = hovering }
      .animation(
        .easeOut(duration: SidebarProminentButtonConstants.stateAnimationDuration),
        value: isHovering
      )
      .animation(
        .easeOut(duration: SidebarProminentButtonConstants.stateAnimationDuration),
        value: configuration.isPressed
      )
  }

  private var label: some View {
    configuration.label
      .foregroundStyle(isActive ? Color.white : Color.primary)
      .font(.callout.weight(.medium))
      .frame(maxWidth: .infinity)
      .padding(.horizontal, SidebarProminentButtonConstants.horizontalPadding)
      .padding(.vertical, SidebarProminentButtonConstants.verticalPadding)
  }

  @ViewBuilder
  private var background: some View {
    #if compiler(>=6.2)
      if #available(macOS 26.0, *) {
        Color.clear
          .glassEffect(
            .regular
              .tint(isActive ? tint : nil)
              .interactive(!isBusy),
            in: Capsule()
          )
      } else {
        fallbackBackground
      }
    #else
      fallbackBackground
    #endif
  }

  /// Hand-drawn hover and press states for macOS before Liquid Glass. The
  /// Human Interface Guidelines require a press state on a custom button, and
  /// `.buttonStyle(.plain)` used to strip it without replacing it.
  private var fallbackBackground: some View {
    Capsule()
      .fill(fallbackFill)
      .overlay(
        Capsule()
          .stroke(
            tint.opacity(
              isActive ? 0 : SidebarProminentButtonConstants.inactiveBorderOpacity),
            lineWidth: SidebarProminentButtonConstants.borderLineWidth
          )
      )
      .opacity(
        configuration.isPressed ? SidebarProminentButtonConstants.pressedOpacity : 1)
  }

  private var fallbackFill: Color {
    guard !isActive else { return tint }
    let base = SidebarProminentButtonConstants.inactiveTintOpacity
    let hovered = base + SidebarProminentButtonConstants.hoverTintBoost
    return tint.opacity(isHovering && !isBusy ? hovered : base)
  }
}
