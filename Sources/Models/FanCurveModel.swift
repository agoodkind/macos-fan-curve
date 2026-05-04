//
//  FanCurveModel.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import AppLog
import Combine
import Foundation

private let fanCurveModelLog = AppLog.make(category: "FanCurveModel")

/// Conservative default for Overdrive's 100% target when no probe result
/// has been written yet. Firmware accepts it on M4 Max and M5 Max.
private let overdriveTargetRPMDefault: Float = 10_000

/// When Overdrive is on, 100% on the curve maps to this value. Prefers
/// the measured value from a Learn probe, falling back to the default.
var overdriveTargetRPM: Float {
    let measured = Float(
        sharedDefaults().double(forKey: SharedConfigKeys.overdriveTargetRPMMeasured))
    return measured > 0 ? measured : overdriveTargetRPMDefault
}

/// Map a curve percent (0...1) to a command for a fan given its reported
/// min/max RPM. Honors the Overdrive and Underdrive settings read from the
/// shared UserDefaults suite so the GUI and the Agent agree.
///
/// Semantics:
/// - percent <= 0 with underdrive off: fan is held at the reported minimum RPM.
/// - percent <= 0 with underdrive on: fan is forced to 0 RPM in manual mode.
/// - percent > 0 with overdrive off: interpolate between minRPM and maxRPM.
/// - percent > 0 with overdrive on: interpolate between minRPM and overdriveTargetRPM.
/// - Underdrive also lowers the floor from minRPM to 0 for above-zero targets.
func fanCommandFor(percent: Double, minRPM: Float, maxRPM: Float) -> FanCommand {
    let defaults = sharedDefaults()
    let overdrive = defaults.bool(forKey: SharedConfigKeys.overdriveEnabled)
    let underdrive = defaults.bool(forKey: SharedConfigKeys.underdriveEnabled)

    return FanCommandMapping(
        overdriveEnabled: overdrive,
        underdriveEnabled: underdrive,
        overdriveTargetRPM: overdriveTargetRPM
    ).command(percent: percent, minRPM: minRPM, maxRPM: maxRPM)
}

/// Access the shared UserDefaults suite used by GUI + Agent.
/// Persists to ~/Library/Preferences/<SHARED_SUITE_ID>.plist
func sharedDefaults() -> UserDefaults {
    UserDefaults(suiteName: generatedSharedSuiteID) ?? .standard
}

class FanCurveModel: ObservableObject {
    @Published var controlPoints: [CurvePoint] {
        didSet { save() }
    }
    @Published var interpolationMode: InterpolationMode {
        didSet { save() }
    }
    @Published var isActive: Bool {
        didSet {
            sharedDefaults().set(isActive, forKey: SharedConfigKeys.curveActive)
        }
    }

    /// Ships as the Apple Silent approximation so a fresh install matches
    /// roughly what macOS would do on its own. The user can pick a more
    /// aggressive preset from Settings if they want.
    static let defaultCurve: [CurvePoint] = CurvePresets.appleSilent.curvePoints()

    static let tempRange: ClosedRange<Double> = CurveColumns.tempRange

    init() {
        let loaded = Self.load()
        self.controlPoints = Self.normalizedCurve(loaded.isEmpty ? Self.defaultCurve : loaded)
        self.interpolationMode = Self.loadMode()
        self.isActive = sharedDefaults().bool(forKey: SharedConfigKeys.curveActive)
    }

    /// Re-samples any imported/saved curve onto the editor's fixed column grid
    /// so presets, learned curves, and legacy saved curves all behave the same.
    private static func normalizedCurve(_ points: [CurvePoint]) -> [CurvePoint] {
        CurveColumns.normalize(points)
    }

    func evaluate(at temperature: Double) -> Double {
        CurveInterpolation.evaluate(at: temperature, points: controlPoints, mode: interpolationMode)
    }

    /// Map a curve percent (0...1) to an RPM target for a specific fan.
    /// Shares its semantics with `fanCommandFor`. Kept for GUI preview uses.
    func rpmForFan(percent: Double, minRPM: Float, maxRPM: Float) -> Float {
        switch fanCommandFor(percent: percent, minRPM: minRPM, maxRPM: maxRPM) {
        case .auto: return minRPM
        case .setRPM(let rpm): return rpm
        }
    }

    func resetToDefault() {
        replaceCurve(Self.defaultCurve)
    }

    func replaceCurve(_ points: [CurvePoint]) {
        controlPoints = Self.normalizedCurve(points)
    }

    func save() {
        let defaults = sharedDefaults()
        do {
            let data = try JSONEncoder().encode(controlPoints)
            defaults.set(data, forKey: SharedConfigKeys.curvePoints)
        } catch {
            fanCurveModelLog.error(
                "curve.save.encode_failed error=\(error.localizedDescription, privacy: .public) recovery=skip-points-write"
            )
        }
        defaults.set(interpolationMode.rawValue, forKey: SharedConfigKeys.interpolationMode)
    }

    private static func load() -> [CurvePoint] {
        guard let data = sharedDefaults().data(forKey: SharedConfigKeys.curvePoints) else { return [] }
        do {
            let points = try JSONDecoder().decode([CurvePoint].self, from: data)
            guard points.count >= 2 else {
                fanCurveModelLog.notice("curve.load.invalid reason=too-few-points recovery=default")
                return []
            }
            return points
        } catch {
            fanCurveModelLog.notice(
                "curve.load.decode_failed error=\(error.localizedDescription, privacy: .public) recovery=default"
            )
            return []
        }
    }

    private static func loadMode() -> InterpolationMode {
        guard let raw = sharedDefaults().string(forKey: SharedConfigKeys.interpolationMode),
            let mode = InterpolationMode(rawValue: raw)
        else { return .catmullRom }
        return mode
    }
}
