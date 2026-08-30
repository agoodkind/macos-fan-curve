//
//  View+SidebarProminentButtonStyle.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-08-01.
//  Copyright © 2026, all rights reserved.
//

import SwiftUI

private enum SidebarProminentButtonConstants {
  // Fallback chrome for macOS versions without Liquid Glass.
  static let horizontalPadding: CGFloat = 14
  static let verticalPadding: CGFloat = 7
  static let inactiveTintOpacity: Double = 0.12
  static let inactiveBorderOpacity: Double = 0.45
  static let borderLineWidth: CGFloat = 0.8
  static let hoverTintBoost: Double = 0.10
  static let pressedOpacity: Double = 0.82
  static let stateAnimationDuration: TimeInterval = 0.12
}

// MARK: - View + sidebarProminentButtonStyle

extension View {
  /// The sidebar's full-width action buttons: Boost, and the setup call to
  /// action. On macOS 26 these are the stock Liquid Glass button styles, so
  /// glass, hover, and press all come from the system. The active state is
  /// the prominent variant, which fills with the tint, and `.tint` carries
  /// each button's own color: orange for Boost, accent for setup. Older
  /// macOS keeps a hand-drawn tinted capsule.
  @ViewBuilder
  func sidebarProminentButtonStyle(
    tint: Color,
    isActive: Bool,
    isBusy: Bool
  ) -> some View {
    #if compiler(>=6.2)
      if #available(macOS 26.0, *) {
        if isActive {
          self.buttonStyle(.glassProminent).tint(tint)
        } else {
          self.buttonStyle(.glass).tint(tint)
        }
      } else {
        self.buttonStyle(
          SidebarProminentFallbackButtonStyle(
            tint: tint, isActive: isActive, isBusy: isBusy))
      }
    #else
      self.buttonStyle(
        SidebarProminentFallbackButtonStyle(
          tint: tint, isActive: isActive, isBusy: isBusy))
    #endif
  }
}

// MARK: - SidebarProminentFallbackButtonStyle

/// Tinted capsule with hand-drawn hover and press states, for macOS versions
/// without Liquid Glass. The Human Interface Guidelines require a press state
/// on a custom button.
struct SidebarProminentFallbackButtonStyle: ButtonStyle {
  let tint: Color
  let isActive: Bool
  let isBusy: Bool

  func makeBody(configuration: Configuration) -> some View {
    SidebarProminentFallbackButtonBody(
      configuration: configuration,
      tint: tint,
      isActive: isActive,
      isBusy: isBusy
    )
  }
}

// MARK: - SidebarProminentFallbackButtonBody

/// A view rather than inline body content, because hover tracking needs
/// `@State` and a `ButtonStyle` is a struct.
private struct SidebarProminentFallbackButtonBody: View {
  let configuration: ButtonStyleConfiguration
  let tint: Color
  let isActive: Bool
  let isBusy: Bool

  @State private var isHovering = false

  var body: some View {
    configuration.label
      .foregroundStyle(isActive ? Color.white : Color.primary)
      .padding(.horizontal, SidebarProminentButtonConstants.horizontalPadding)
      .padding(.vertical, SidebarProminentButtonConstants.verticalPadding)
      .background { capsuleBackground }
      .contentShape(Capsule())
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

  private var capsuleBackground: some View {
    Capsule()
      .fill(fill)
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

  private var fill: Color {
    guard !isActive else { return tint }
    let base = SidebarProminentButtonConstants.inactiveTintOpacity
    let hovered = base + SidebarProminentButtonConstants.hoverTintBoost
    return tint.opacity(isHovering && !isBusy ? hovered : base)
  }
}
