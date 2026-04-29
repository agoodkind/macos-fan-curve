//
//  TemperatureUnit.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-16.
//  Copyright © 2026
//

import Foundation

/// User-facing temperature unit preference.
/// Values persist in UserDefaults.standard under the key 'temperatureUnit'.
enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }

    var displayName: String {
        switch self {
        case .celsius: return L10n.tr("Celsius")
        case .fahrenheit: return L10n.tr("Fahrenheit")
        }
    }

    /// Convert a value stored in Celsius to this unit.
    func convert(fromCelsius celsius: Double) -> Double {
        switch self {
        case .celsius: return celsius
        case .fahrenheit: return celsius * 9.0 / 5.0 + 32.0
        }
    }

    static var current: TemperatureUnit {
        let raw = UserDefaults.standard.string(forKey: "temperatureUnit") ?? ""
        return TemperatureUnit(rawValue: raw) ?? .celsius
    }
}
