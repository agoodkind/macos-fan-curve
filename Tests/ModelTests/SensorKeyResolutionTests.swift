//
//  SensorKeyResolutionTests.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-27.
//  Copyright © 2026, all rights reserved.
//

import Nimble
import XCTest

@testable import FanCurveModels

/// In-memory stand-in for `XPCClient.enumerateKeys()`. The real client
/// needs a privileged helper; this fake lets tests drive the resolution
/// boundary with a scripted discovery result, including the "could not
/// enumerate" case the real client also represents as an empty array.
private struct FakeSMCKeyDiscoverer: SMCKeyDiscovering {
  let keysToReturn: [String]

  func enumerateKeys() async -> [String] {
    keysToReturn
  }
}

final class SensorKeyResolutionTests: XCTestCase {
  private let catalogTempKeys = ["TC0P", "TCAD", "Tp01", "Tg0U"]
  private let catalogCPUTempKeys: Set<String> = ["TC0P", "TCAD", "Tp01"]

  func testResolve_KeepsReportedKeyAndDropsUnreportedCatalogKey() {
    // The machine reports every catalog key except TCAD.
    let discoveredKeys = ["TC0P", "Tp01", "Tg0U", "F0Ac"]

    let resolved = SensorKeyResolver.resolve(
      catalogTempKeys: catalogTempKeys,
      catalogCPUTempKeys: catalogCPUTempKeys,
      discoveredKeys: discoveredKeys
    )

    expect(resolved.usedFallback).to(beFalse())
    expect(resolved.tempKeys).to(contain("TC0P"))
    expect(resolved.tempKeys).notTo(contain("TCAD"))
    expect(resolved.excludedKeys).to(equal(["TCAD"]))
    expect(resolved.cpuTempKeys).to(equal(["TC0P", "Tp01"]))
  }

  func testResolve_TransportFailureDoesNotPruneAnything() {
    // enumerateKeys() returns [] both when the helper truly has no keys
    // and when it could not be reached. Resolution must treat this as
    // "unknown" and fall back to the full catalog rather than pruning.
    let resolved = SensorKeyResolver.resolve(
      catalogTempKeys: catalogTempKeys,
      catalogCPUTempKeys: catalogCPUTempKeys,
      discoveredKeys: []
    )

    expect(resolved.usedFallback).to(beTrue())
    expect(resolved.fallbackReason).to(equal(.enumerationUnavailable))
    expect(resolved.tempKeys).to(equal(catalogTempKeys))
    expect(resolved.cpuTempKeys).to(equal(catalogCPUTempKeys))
    expect(resolved.excludedKeys).to(beEmpty())
  }

  func testResolve_FallsBackWhenNoCPUKeySurvives() {
    // Enumeration succeeds and reports real keys, but none of them are
    // catalog CPU keys (an unrecognised hw.model or a catalog miss).
    // Controlling nothing is worse than probing the full catalog.
    let discoveredKeys = ["Tg0U", "F0Ac", "FNum"]

    let resolved = SensorKeyResolver.resolve(
      catalogTempKeys: catalogTempKeys,
      catalogCPUTempKeys: catalogCPUTempKeys,
      discoveredKeys: discoveredKeys
    )

    expect(resolved.usedFallback).to(beTrue())
    expect(resolved.fallbackReason).to(equal(.noCPUKeySurvived))
    expect(resolved.tempKeys).to(equal(catalogTempKeys))
    expect(resolved.cpuTempKeys).to(equal(catalogCPUTempKeys))
    expect(resolved.cpuTempKeys).notTo(beEmpty())
  }

  func testResolveWithDiscoverer_KeepsReportedKeyThroughAsyncBoundary() async {
    let discoverer = FakeSMCKeyDiscoverer(keysToReturn: ["TC0P", "Tp01", "Tg0U"])

    let resolved = await SensorKeyResolver.resolve(
      catalogTempKeys: catalogTempKeys,
      catalogCPUTempKeys: catalogCPUTempKeys,
      discoverer: discoverer
    )

    expect(resolved.usedFallback).to(beFalse())
    expect(resolved.excludedKeys).to(equal(["TCAD"]))
    expect(resolved.cpuTempKeys).to(equal(["TC0P", "Tp01"]))
  }
}
