//
//  FanCurveCommandTests.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-02.
//  Copyright © 2026, all rights reserved.
//

import Nimble
import XCTest

@testable import FanCurveModels

final class FanCurveCommandTests: XCTestCase {
    func testRuntimeAffordancesPreserveStringJSONPayloads() throws {
        let data = try JSONEncoder().encode(SetupActionAffordance.approveBackgroundAgent)
        let string = String(data: data, encoding: .utf8)
        let decoded = try JSONDecoder().decode(SetupActionAffordance.self, from: data)

        expect(string) == "\"approveBackgroundAgent\""
        expect(decoded) == .approveBackgroundAgent
    }

    func testZeroPercentCommandsMinimumRPMWhenUnderdriveIsOff() {
        let mapping = FanCommandMapping(
            overdriveEnabled: false,
            underdriveEnabled: false,
            overdriveTargetRPM: 10_000)

        let command = mapping.command(percent: 0, minRPM: 2_317, maxRPM: 7_826)

        expect(self.rpm(command)) == 2_317
    }

    func testZeroPercentCommandsZeroRPMWhenUnderdriveIsOn() {
        let mapping = FanCommandMapping(
            overdriveEnabled: false,
            underdriveEnabled: true,
            overdriveTargetRPM: 10_000)

        let command = mapping.command(percent: 0, minRPM: 2_317, maxRPM: 7_826)

        expect(self.rpm(command)) == 0
    }

    private func rpm(_ command: FanCommand) -> Float? {
        guard case .setRPM(let rpm) = command else { return nil }
        return rpm
    }
}
