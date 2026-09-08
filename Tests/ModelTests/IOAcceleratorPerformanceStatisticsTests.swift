//
//  IOAcceleratorPerformanceStatisticsTests.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-09-07.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import IOKit
import Nimble
import XCTest

@testable import FanCurveModels

final class IOAcceleratorPerformanceStatisticsTests: XCTestCase {
  func testRepeatedReadsFromLiveRegistryComplete() throws {
    try XCTSkipUnless(
      try hasDeviceUtilizationStatistic(),
      "This host has no IOAccelerator device utilization statistic."
    )
    let unavailable = -1.0
    for _ in 0..<1_000 {
      let utilization = autoreleasepool {
        readIOAcceleratorDeviceUtilizationPercent(defaultValue: unavailable)
      }
      expect((0...100).contains(utilization)) == true
    }
  }

  private func hasDeviceUtilizationStatistic() throws -> Bool {
    var iterator: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(
      kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator
    )
    guard result == KERN_SUCCESS else {
      throw NSError(domain: NSMachErrorDomain, code: Int(result))
    }
    defer { IOObjectRelease(iterator) }

    while case let entry = IOIteratorNext(iterator), entry != 0 {
      defer { IOObjectRelease(entry) }
      if let property = IORegistryEntryCreateCFProperty(
        entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0
      )?.takeRetainedValue(),
        let statistics = property as? NSDictionary,
        statistics["Device Utilization %"] is NSNumber
      {
        return true
      }
    }
    return false
  }
}
