//
//  SettingsSliderRow.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-24.
//  Copyright © 2026
//

import AppKit
import SwiftUI

struct SettingsDangerToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsAccessoryRow(
            minimumLabelWidth: 220,
            accessoryWidth: SettingsFormComponents.switchAccessoryWidth,
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
    let maximum: String
    let midpoint: String?

    init(minimum: String, maximum: String, midpoint: String? = nil) {
        self.minimum = minimum
        self.maximum = maximum
        self.midpoint = midpoint
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
            .frame(height: SettingsFormComponents.sliderControlHeight)
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

@MainActor
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

    @MainActor
    final class Coordinator: NSObject {
        var value: Binding<Double>

        init(value: Binding<Double>) {
            self.value = value
        }

        @objc
        @MainActor
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
        iconColor: Color = Color(nsColor: .systemOrange),
        iconSystemName: String? = nil
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
