//
//  SettingsFormComponents.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-11.
//  Copyright © 2026
//

import AppKit
import SwiftUI

private let settingsSliderControlHeight: CGFloat = 22
private let settingsSwitchAccessoryWidth: CGFloat = 56
private let settingsDisclosureChevronWidth: CGFloat = 12
private let settingsDisclosureTitleSpacing: CGFloat = 8
private let settingsDisclosureContentLeadingPadding = settingsDisclosureChevronWidth + settingsDisclosureTitleSpacing
private let settingsDisclosureAnimationDuration: TimeInterval = 0.18
private let settingsDisclosureAnimation = Animation.easeInOut(duration: settingsDisclosureAnimationDuration)

struct SettingsFormContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            Form {
                content()
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
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

struct SettingsAccessoryRow<Label: View, Accessory: View>: View {
    let minimumLabelWidth: CGFloat
    let accessoryWidth: CGFloat?
    let spacing: CGFloat
    let stackedSpacing: CGFloat
    @ViewBuilder let label: () -> Label
    @ViewBuilder let accessory: () -> Accessory

    init(
        minimumLabelWidth: CGFloat = 180,
        accessoryWidth: CGFloat? = nil,
        spacing: CGFloat = 12,
        stackedSpacing: CGFloat = 6,
        @ViewBuilder label: @escaping () -> Label,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.minimumLabelWidth = minimumLabelWidth
        self.accessoryWidth = accessoryWidth
        self.spacing = spacing
        self.stackedSpacing = stackedSpacing
        self.label = label
        self.accessory = accessory
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: spacing) {
                label()
                    .frame(minWidth: minimumLabelWidth, maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(2)

                accessoryContainer
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: stackedSpacing) {
                label()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(2)

                accessoryContainer
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .frame(width: 112, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .layoutPriority(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Text(value)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
            HStack(alignment: .center, spacing: 12) {
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
        contentSpacing: CGFloat = 8,
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
                HStack(alignment: .center, spacing: settingsDisclosureTitleSpacing) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: settingsDisclosureChevronWidth)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(settingsDisclosureAnimation, value: isExpanded)
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
                .padding(.top, 10)
                .padding(.leading, settingsDisclosureContentLeadingPadding)
                .readSettingsDisclosureContentHeight { height in
                    contentHeight = height
                }
                .frame(height: contentIsVisible ? contentHeight : 0, alignment: .top)
                .clipped()
                .opacity(contentIsVisible ? 1 : 0)
                .offset(y: contentIsVisible ? 0 : -4)
                .animation(settingsDisclosureAnimation, value: contentIsVisible)
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

    private func updateContentVisibility(isExpanded: Bool) {
        if isExpanded {
            rendersContent = true
            contentIsVisible = false

            DispatchQueue.main.async {
                withAnimation(settingsDisclosureAnimation) {
                    contentIsVisible = true
                }
            }
        } else {
            withAnimation(settingsDisclosureAnimation) {
                contentIsVisible = false
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + settingsDisclosureAnimationDuration) {
                if !self.isExpanded {
                    rendersContent = false
                }
            }
        }
    }
}

private struct SettingsDisclosureContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    fileprivate func readSettingsDisclosureContentHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SettingsDisclosureContentHeightPreferenceKey.self,
                    value: proxy.size.height
                )
            }
        }
        .onPreferenceChange(SettingsDisclosureContentHeightPreferenceKey.self, perform: onChange)
    }
}

private struct SettingsDangerStatusBadge: View {
    let status: String

    var body: some View {
        Label {
            Text(status)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color(nsColor: .systemOrange))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct SettingsDangerToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsAccessoryRow(
            minimumLabelWidth: 220,
            accessoryWidth: settingsSwitchAccessoryWidth,
            spacing: 16
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                SettingsDescription(text: description)
            }
        } accessory: {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .help(description)
        }
        .padding(.vertical, 2)
    }
}

struct SettingsSliderScaleLabels {
    let minimum: String
    let midpoint: String?
    let maximum: String

    init(minimum: String, midpoint: String? = nil, maximum: String) {
        self.minimum = minimum
        self.midpoint = midpoint
        self.maximum = maximum
    }
}

struct SettingsSliderRow: View {
    let title: String
    let description: String
    let displayValue: String
    let range: ClosedRange<Double>
    let step: Double?
    let scaleLabels: SettingsSliderScaleLabels?
    let help: String?
    @Binding var value: Double

    init(
        title: String,
        description: String,
        displayValue: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double? = nil,
        scaleLabels: SettingsSliderScaleLabels? = nil,
        help: String? = nil
    ) {
        self.title = title
        self.description = description
        self.displayValue = displayValue
        self._value = value
        self.range = range
        self.step = step
        self.scaleLabels = scaleLabels
        self.help = help
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    SettingsDescription(text: description)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(2)

                Text(displayValue)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                sliderControl

                if let scaleLabels {
                    scaleLabelRow(scaleLabels)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sliderControl: some View {
        SettingsFullWidthSlider(value: sliderBinding, range: range, help: help ?? description)
            .frame(height: settingsSliderControlHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: { value },
            set: { newValue in
                value = steppedValue(newValue)
            }
        )
    }

    private func steppedValue(_ newValue: Double) -> Double {
        guard let step else { return min(max(newValue, range.lowerBound), range.upperBound) }

        let stepped = (newValue / step).rounded() * step
        return min(max(stepped, range.lowerBound), range.upperBound)
    }

    private func scaleLabelRow(_ scaleLabels: SettingsSliderScaleLabels) -> some View {
        HStack(spacing: 0) {
            Text(scaleLabels.minimum)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let midpoint = scaleLabels.midpoint {
                Text(midpoint)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            Text(scaleLabels.maximum)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsFullWidthSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let help: String

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value)
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(
            value: value,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            target: context.coordinator,
            action: #selector(Coordinator.valueChanged(_:))
        )
        slider.isContinuous = true
        slider.toolTip = help
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        slider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return slider
    }

    func updateNSView(_ slider: NSSlider, context: Context) {
        context.coordinator.value = $value
        slider.minValue = range.lowerBound
        slider.maxValue = range.upperBound
        slider.toolTip = help

        if slider.doubleValue != value {
            slider.doubleValue = value
        }
    }

    final class Coordinator: NSObject {
        var value: Binding<Double>

        init(value: Binding<Double>) {
            self.value = value
        }

        @objc
        func valueChanged(_ sender: NSSlider) {
            value.wrappedValue = sender.doubleValue
        }
    }
}

struct SettingsToggleDescriptionRow: View {
    let title: String
    let description: String
    let iconSystemName: String?
    let iconColor: Color
    @Binding var isOn: Bool

    init(
        title: String,
        description: String,
        isOn: Binding<Bool>,
        iconSystemName: String? = nil,
        iconColor: Color = Color(nsColor: .systemOrange)
    ) {
        self.title = title
        self.description = description
        self._isOn = isOn
        self.iconSystemName = iconSystemName
        self.iconColor = iconColor
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let iconSystemName {
                    Image(systemName: iconSystemName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    SettingsDescription(text: description)
                }
            }
        }
    }
}
