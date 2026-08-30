//
//  LoadAssistStoreTests.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-06-04.
//  Copyright © 2026, all rights reserved.
//

import Nimble
import XCTest

@testable import FanCurveModels

final class LoadAssistStoreTests: XCTestCase {
  private var defaults: UserDefaults?
  private var suiteName: String?

  override func setUp() {
    super.setUp()
    suiteName = "LoadAssistStoreTests.\(UUID().uuidString)"
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

  func testDefaultPointsUseApprovedDefaultShape() {
    let points = LoadAssistStore.defaultPoints()

    expect(points.map(\.temperature)) == [0.0, 55.0, 70.0, 100.0]
    expect(points.map(\.fanPercent)) == [0.0, 0.0, 0.6, 0.6]
  }

  func testNormalizedPointsPreserveSavedUsageThresholdsAndMonotonicPercents() {
    let points = [
      CurvePoint(temperature: 0, fanPercent: 0.2),
      CurvePoint(temperature: 60, fanPercent: 0.1),
      CurvePoint(temperature: 80, fanPercent: 0.8),
      CurvePoint(temperature: 100, fanPercent: 0.7),
    ]

    let normalized = LoadAssistStore.normalizedPoints(points)

    expect(normalized.map(\.temperature)) == [0.0, 60.0, 80.0, 100.0]
    expect(normalized.map(\.fanPercent)) == [0.2, 0.2, 0.8, 0.8]
  }

  func testLoadPointsHardCutsLegacyCurveToDefaultShape() throws {
    guard let defaults else {
      fail("Expected test defaults")
      return
    }
    let oldPoints = [
      CurvePoint(temperature: 0, fanPercent: 0.0),
      CurvePoint(temperature: 60, fanPercent: 0.1),
      CurvePoint(temperature: 80, fanPercent: 0.75),
      CurvePoint(temperature: 100, fanPercent: 0.75),
    ]
    let data = try JSONEncoder().encode(oldPoints)
    defaults.set(data, forKey: LoadAssistKind.cpu.curvePointsKey)
    defaults.set(
      LoadAssistStoreMigrationVersion.legacyFixedColumnReset,
      forKey: SharedConfigKeys.loadAssistMigrationVersion
    )

    let loaded = LoadAssistStore.loadPoints(.cpu, defaults: defaults)
    let defaultPoints = LoadAssistStore.defaultPoints()

    expect(loaded.map(\.temperature)) == defaultPoints.map(\.temperature)
    expect(loaded.map(\.fanPercent)) == defaultPoints.map(\.fanPercent)
  }

  func testLoadPointsPreserveSavedNumericCurveAtCurrentVersion() throws {
    guard let defaults else {
      fail("Expected test defaults")
      return
    }
    let savedPoints = [
      CurvePoint(temperature: 0, fanPercent: 0.0),
      CurvePoint(temperature: 58, fanPercent: 0.15),
      CurvePoint(temperature: 82, fanPercent: 0.65),
      CurvePoint(temperature: 100, fanPercent: 0.65),
    ]
    let data = try JSONEncoder().encode(savedPoints)
    defaults.set(data, forKey: LoadAssistKind.gpu.curvePointsKey)
    defaults.set(
      LoadAssistStoreMigrationVersion.current,
      forKey: SharedConfigKeys.loadAssistMigrationVersion
    )

    let loaded = LoadAssistStore.loadPoints(.gpu, defaults: defaults)

    expect(loaded.map(\.temperature)) == [0.0, 58.0, 82.0, 100.0]
    expect(loaded.map(\.fanPercent)) == [0.0, 0.15, 0.65, 0.65]
  }

  func testUpdatedPointsAllowsInteriorUsageDragAndAnchorsEndpoints() {
    let points = [
      CurvePoint(temperature: 0, fanPercent: 0.0),
      CurvePoint(temperature: 55, fanPercent: 0.0),
      CurvePoint(temperature: 70, fanPercent: 0.6),
      CurvePoint(temperature: 100, fanPercent: 0.6),
    ]

    let updated = LoadAssistStore.updatedPoints(
      points,
      draggedIndex: 1,
      proposedLoad: 62,
      proposedPercent: 0.1
    )
    let anchored = LoadAssistStore.updatedPoints(
      points,
      draggedIndex: 0,
      proposedLoad: 15,
      proposedPercent: 0.05
    )

    expect(updated.map(\.temperature)) == [0.0, 62.0, 70.0, 100.0]
    expect(updated.map(\.fanPercent)) == [0.0, 0.1, 0.6, 0.6]
    expect(anchored.first?.temperature) == 0.0
  }

  func testUpdatedPointsKeepPercentsMonotonicWhenDraggedAboveRightNeighbor() {
    let points = [
      CurvePoint(temperature: 0, fanPercent: 0.1),
      CurvePoint(temperature: 55, fanPercent: 0.3),
      CurvePoint(temperature: 70, fanPercent: 0.6),
      CurvePoint(temperature: 100, fanPercent: 0.8),
    ]

    let updated = LoadAssistStore.updatedPoints(
      points,
      draggedIndex: 1,
      proposedLoad: 60,
      proposedPercent: 0.95
    )

    expect(updated.map(\.fanPercent)) == [0.1, 0.95, 0.95, 0.95]
  }
}

// MARK: - LoadAssistStoreMigrationVersion

private enum LoadAssistStoreMigrationVersion {
  static let legacyFixedColumnReset = 4
  static let current = 5
}
