//
//  SettingsFormComponents.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-11.
//  Copyright © 2026
//

import AppKit
import SwiftUI

enum SettingsFormComponents {
    static let sliderControlHeight: CGFloat = 22
    static let switchAccessoryWidth: CGFloat = 56
    static let disclosureChevronWidth: CGFloat = 12
    static let disclosureTitleSpacing: CGFloat = 8
    static let disclosureContentLeadingPadding =
        disclosureChevronWidth + disclosureTitleSpacing
    static let disclosureAnimationDuration: TimeInterval = 0.18
    static let disclosureAnimation = Animation.easeInOut(
        duration: disclosureAnimationDuration
    )
}

private enum SettingsFormComponentsConstants {
    static let accessoryRowDefaultMinLabelWidth: CGFloat = 180
    static let accessoryRowDefaultSpacing: CGFloat = 12
    static let keyValueRowSpacing: CGFloat = 12
    static let keyValueLabelWidth: CGFloat = 112
    static let dangerDisclosureTitleSpacing: CGFloat = 12
    static let disclosureDefaultContentSpacing: CGFloat = 8
    static let disclosureChevronExpandedRotation: Double = 90
    static let disclosureContentTopPadding: CGFloat = 10
    static let disclosureContentCollapseOffset: CGFloat = -4
    static let accessoryRowLabelLayoutPriority: Double = 2
    static let keyValueRowValueLineLimit: Int = 2
    static let keyValueRowValueLayoutPriority: Double = 2
    static let titleCaptionSpacing: CGFloat = 2
    static let titleCaptionIconSpacing: CGFloat = 6
}

struct SettingsFormContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Form {
            content()
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct SettingsDescription: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A title stacked over a secondary caption, the shared label block used by the
/// slider, toggle, and danger-toggle rows. An optional leading icon lets it also
/// back the inline toggle-description layout.
struct SettingsTitleCaption: View {
    let title: String
    let caption: String
    let iconSystemName: String?
    let iconColor: Color

    init(
        title: String,
        caption: String,
        iconSystemName: String? = nil,
        iconColor: Color = Color(nsColor: .systemOrange)
    ) {
        self.title = title
        self.caption = caption
        self.iconSystemName = iconSystemName
        self.iconColor = iconColor
    }

    var body: some View {
        if let iconSystemName {
            HStack(
                alignment: .firstTextBaseline,
                spacing: SettingsFormComponentsConstants.titleCaptionIconSpacing
            ) {
                Image(systemName: iconSystemName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(iconColor)
                labelStack
            }
        } else {
            labelStack
        }
    }

    private var labelStack: some View {
        VStack(alignment: .leading, spacing: SettingsFormComponentsConstants.titleCaptionSpacing) {
            Text(title)
            SettingsDescription(text: caption)
        }
    }
}

struct SettingsAccessoryRow<Label: View, Accessory: View>: View {
    let minimumLabelWidth: CGFloat
    let accessoryWidth: CGFloat?
    let spacing: CGFloat
    @ViewBuilder let label: () -> Label
    @ViewBuilder let accessory: () -> Accessory

    init(
        minimumLabelWidth: CGFloat = SettingsFormComponentsConstants
            .accessoryRowDefaultMinLabelWidth,
        accessoryWidth: CGFloat? = nil,
        spacing: CGFloat = SettingsFormComponentsConstants.accessoryRowDefaultSpacing,
        @ViewBuilder label: @escaping () -> Label,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.minimumLabelWidth = minimumLabelWidth
        self.accessoryWidth = accessoryWidth
        self.spacing = spacing
        self.label = label
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            label()
                .frame(minWidth: minimumLabelWidth, maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(SettingsFormComponentsConstants.accessoryRowLabelLayoutPriority)

            accessoryContainer
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var accessoryContainer: some View {
        if let accessoryWidth {
            accessory()
                .frame(width: accessoryWidth, alignment: .trailing)
        } else {
            accessory()
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct SettingsKeyValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(
            alignment: .firstTextBaseline,
            spacing: SettingsFormComponentsConstants.keyValueRowSpacing
        ) {
            Text(label)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .frame(
                    width: SettingsFormComponentsConstants.keyValueLabelWidth, alignment: .leading
                )
                .lineLimit(1)
                .truncationMode(.tail)

            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(SettingsFormComponentsConstants.keyValueRowValueLineLimit)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .layoutPriority(SettingsFormComponentsConstants.keyValueRowValueLayoutPriority)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.caption)
    }
}

struct SettingsDangerDisclosure<Content: View>: View {
    let title: String
    let status: String?
    @ViewBuilder let content: () -> Content

    @State private var isExpanded = false

    init(
        title: String,
        status: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.status = status
        self.content = content
    }

    var body: some View {
        SettingsAnimatedDisclosure(isExpanded: $isExpanded) {
            HStack(
                alignment: .center,
                spacing: SettingsFormComponentsConstants.dangerDisclosureTitleSpacing
            ) {
                Text(title)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let status {
                    SettingsDangerStatusBadge(status: status)
                }
            }
        } content: {
            content()
        }
    }
}

struct SettingsAnimatedDisclosure<Label: View, Content: View>: View {
    @Binding var isExpanded: Bool
    let contentSpacing: CGFloat
    @ViewBuilder let label: () -> Label
    @ViewBuilder let content: () -> Content

    @State private var rendersContent = false
    @State private var contentIsVisible = false
    @State private var contentHeight: CGFloat = 0

    init(
        isExpanded: Binding<Bool>,
        contentSpacing: CGFloat = SettingsFormComponentsConstants.disclosureDefaultContentSpacing,
        @ViewBuilder label: @escaping () -> Label,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self._isExpanded = isExpanded
        self.contentSpacing = contentSpacing
        self.label = label
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                setExpanded(!isExpanded)
            } label: {
                HStack(alignment: .center, spacing: SettingsFormComponents.disclosureTitleSpacing) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: SettingsFormComponents.disclosureChevronWidth)
                        .rotationEffect(
                            .degrees(
                                isExpanded
                                    ? SettingsFormComponentsConstants
                                        .disclosureChevronExpandedRotation : 0)
                        )
                        .animation(SettingsFormComponents.disclosureAnimation, value: isExpanded)
                        .accessibilityHidden(true)

                    label()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .transaction { transaction in
                transaction.animation = nil
            }

            if rendersContent {
                VStack(alignment: .leading, spacing: contentSpacing) {
                    content()
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, SettingsFormComponentsConstants.disclosureContentTopPadding)
                .padding(.leading, SettingsFormComponents.disclosureContentLeadingPadding)
                .readSettingsDisclosureContentHeight { height in
                    updateMeasuredContentHeight(height)
                }
                .frame(height: disclosureContentFrameHeight, alignment: .top)
                .clipped()
                .opacity(contentIsVisible ? 1 : 0)
                .offset(
                    y: contentIsVisible
                        ? 0 : SettingsFormComponentsConstants.disclosureContentCollapseOffset
                )
                .animation(SettingsFormComponents.disclosureAnimation, value: contentIsVisible)
            }
        }
        .onAppear {
            rendersContent = isExpanded
            contentIsVisible = isExpanded
        }
        .onChange(of: isExpanded) { newValue in
            updateContentVisibility(isExpanded: newValue)
        }
    }

    private func setExpanded(_ newValue: Bool) {
        isExpanded = newValue
    }

    private var disclosureContentFrameHeight: CGFloat? {
        if !contentIsVisible {
            return 0
        }

        if contentHeight > 0 {
            return contentHeight
        }

        return nil
    }

    private func updateMeasuredContentHeight(_ height: CGFloat) {
        guard height > 0 else {
            return
        }

        contentHeight = height
    }

    private func updateContentVisibility(isExpanded: Bool) {
        if isExpanded {
            rendersContent = true
            contentIsVisible = false

            DispatchQueue.main.async {
                withAnimation(SettingsFormComponents.disclosureAnimation) {
                    contentIsVisible = true
                }
            }
        } else {
            withAnimation(SettingsFormComponents.disclosureAnimation) {
                contentIsVisible = false
            }

            DispatchQueue.main.asyncAfter(
                deadline: .now() + SettingsFormComponents.disclosureAnimationDuration
            ) {
                if !self.isExpanded {
                    rendersContent = false
                }
            }
        }
    }
}

private struct SettingsDisclosureHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    func readSettingsDisclosureContentHeight(
        _ onChange: @escaping (CGFloat) -> Void
    ) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SettingsDisclosureHeightKey.self,
                    value: proxy.size.height
                )
            }
        }
        .onPreferenceChange(SettingsDisclosureHeightKey.self, perform: onChange)
    }
}
