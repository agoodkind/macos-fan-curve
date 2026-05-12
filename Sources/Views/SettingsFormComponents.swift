//
//  SettingsFormComponents.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-11.
//  Copyright © 2026
//

import SwiftUI

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
    let description: String
    @ViewBuilder let content: () -> Content

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(.top, 6)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(nsColor: .systemOrange))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    SettingsDescription(text: description)
                }
            }
        }
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
                Slider(value: sliderBinding, in: range)
                    .help(help ?? description)

                if let scaleLabels {
                    scaleLabelRow(scaleLabels)
                }
            }
        }
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
