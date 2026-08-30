//
//  ExpandedRangeConfigurationStoreTests.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-08-30.
//  Copyright © 2026, all rights reserved.
//

import Nimble
import XCTest

@testable import FanCurveModels

final class ExpandedRangeConfigurationStoreTests: XCTestCase {
  private var defaults: UserDefaults?
  private var suiteName: String?

  override func setUp() {
    super.setUp()
    suiteName = "ExpandedRangeConfigurationStoreTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)
  }

  override func tearDown() {
    if let defaults, let suiteName {
      defaults.removePersistentDomain(forName: suiteName)
    }
    defaults = nil
    suiteName = nil
    super.tearDown()
  }

  func testMigrationDisablesAccessForFreshInstall() throws {
    let defaults = try requiredDefaults()

    ExpandedRangeConfigurationStore.migrateIfNeeded(defaults: defaults)

    expect(
      defaults.object(forKey: SharedConfigKeys.extendedRangeConfigurationAllowed)
    ).toNot(beNil())
    expect(defaults.bool(forKey: SharedConfigKeys.extendedRangeConfigurationAllowed)) == false
  }

  func testMigrationEnablesAccessForExistingOverdrive() throws {
    let defaults = try requiredDefaults()
    defaults.set(true, forKey: SharedConfigKeys.overdriveEnabled)

    ExpandedRangeConfigurationStore.migrateIfNeeded(defaults: defaults)

    expect(defaults.bool(forKey: SharedConfigKeys.extendedRangeConfigurationAllowed)) == true
  }

  func testMigrationEnablesAccessForExistingUnderdrive() throws {
    let defaults = try requiredDefaults()
    defaults.set(true, forKey: SharedConfigKeys.underdriveEnabled)

    ExpandedRangeConfigurationStore.migrateIfNeeded(defaults: defaults)

    expect(defaults.bool(forKey: SharedConfigKeys.extendedRangeConfigurationAllowed)) == true
  }

  func testMigrationPreservesExistingAccessValue() throws {
    let defaults = try requiredDefaults()
    defaults.set(false, forKey: SharedConfigKeys.extendedRangeConfigurationAllowed)
    defaults.set(true, forKey: SharedConfigKeys.overdriveEnabled)

    ExpandedRangeConfigurationStore.migrateIfNeeded(defaults: defaults)

    expect(defaults.bool(forKey: SharedConfigKeys.extendedRangeConfigurationAllowed)) == false
  }

  func testDisablingAccessClearsLegacyModes() throws {
    let defaults = try requiredDefaults()
    defaults.set(true, forKey: SharedConfigKeys.overdriveEnabled)
    defaults.set(true, forKey: SharedConfigKeys.underdriveEnabled)

    ExpandedRangeConfigurationStore.setAllowed(false, defaults: defaults)

    expect(defaults.bool(forKey: SharedConfigKeys.extendedRangeConfigurationAllowed)) == false
    expect(defaults.bool(forKey: SharedConfigKeys.overdriveEnabled)) == false
    expect(defaults.bool(forKey: SharedConfigKeys.underdriveEnabled)) == false
  }

  private func requiredDefaults() throws -> UserDefaults {
    try XCTUnwrap(defaults)
  }
}
