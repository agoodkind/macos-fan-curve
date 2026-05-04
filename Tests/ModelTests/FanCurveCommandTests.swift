//
//  FanCurveCommandTests.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-02.
//  Copyright © 2026
//

import Nimble
import XCTest

@testable import FanCurveModels

final class FanCurveCommandTests: XCTestCase {
    func testZeroPercentCommandsMinimumRPMWhenUnderdriveIsOff() {
        let mapping = FanCommandMapping(
            overdriveEnabled: false,
            underdriveEnabled: false,
            overdriveTargetRPM: 10_000)

        let command = mapping.command(percent: 0, minRPM: 2_317, maxRPM: 7_826)

        expect(self.rpm(command)).to(equal(2_317))
    }

    func testZeroPercentCommandsZeroRPMWhenUnderdriveIsOn() {
        let mapping = FanCommandMapping(
            overdriveEnabled: false,
            underdriveEnabled: true,
            overdriveTargetRPM: 10_000)

        let command = mapping.command(percent: 0, minRPM: 2_317, maxRPM: 7_826)

        expect(self.rpm(command)).to(equal(0))
    }

    private func rpm(_ command: FanCommand) -> Float? {
        guard case .setRPM(let rpm) = command else { return nil }
        return rpm
    }
}
