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
    let testDefaults = try requiredDefaults()

    ExpandedRangeConfigurationStore.migrateIfNeeded(defaults: testDefaults)

    expect(
      testDefaults.object(forKey: SharedConfigKeys.extendedRangeConfigurationAllowed)
    ) != nil
    expect(testDefaults.bool(forKey: SharedConfigKeys.extendedRangeConfigurationAllowed)) == false
  }

  func testMigrationEnablesAccessForExistingOverdrive() throws {
    let testDefaults = try requiredDefaults()
    testDefaults.set(true, forKey: SharedConfigKeys.overdriveEnabled)

    ExpandedRangeConfigurationStore.migrateIfNeeded(defaults: testDefaults)

    expect(testDefaults.bool(forKey: SharedConfigKeys.extendedRangeConfigurationAllowed)) == true
  }

  func testMigrationEnablesAccessForExistingUnderdrive() throws {
    let testDefaults = try requiredDefaults()
    testDefaults.set(true, forKey: SharedConfigKeys.underdriveEnabled)

    ExpandedRangeConfigurationStore.migrateIfNeeded(defaults: testDefaults)

    expect(testDefaults.bool(forKey: SharedConfigKeys.extendedRangeConfigurationAllowed)) == true
  }

  func testMigrationPreservesExistingAccessValue() throws {
    let testDefaults = try requiredDefaults()
    testDefaults.set(false, forKey: SharedConfigKeys.extendedRangeConfigurationAllowed)
    testDefaults.set(true, forKey: SharedConfigKeys.overdriveEnabled)

    ExpandedRangeConfigurationStore.migrateIfNeeded(defaults: testDefaults)

    expect(testDefaults.bool(forKey: SharedConfigKeys.extendedRangeConfigurationAllowed)) == false
  }

  func testDisablingAccessClearsLegacyModes() throws {
    let testDefaults = try requiredDefaults()
    testDefaults.set(true, forKey: SharedConfigKeys.overdriveEnabled)
    testDefaults.set(true, forKey: SharedConfigKeys.underdriveEnabled)

    ExpandedRangeConfigurationStore.setAllowed(false, defaults: testDefaults)

    expect(testDefaults.bool(forKey: SharedConfigKeys.extendedRangeConfigurationAllowed)) == false
    expect(testDefaults.bool(forKey: SharedConfigKeys.overdriveEnabled)) == false
    expect(testDefaults.bool(forKey: SharedConfigKeys.underdriveEnabled)) == false
  }

  private func requiredDefaults() throws -> UserDefaults {
    try XCTUnwrap(defaults)
  }
}
