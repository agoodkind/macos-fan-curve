//
//  IOAcceleratorPerformanceStatistics.swift
//  FanCurve
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-05-24.
//  Copyright © 2026, all rights reserved.
//

import Foundation
import IOKit

private let ioAcceleratorPerformanceStatisticsKey = "PerformanceStatistics"
private let ioAcceleratorDeviceUtilizationKey = "Device Utilization %"

func readIOAcceleratorDeviceUtilizationPercent(defaultValue: Double) -> Double {
  var iterator: io_iterator_t = 0
  let result = IOServiceGetMatchingServices(
    kIOMainPortDefault,
    IOServiceMatching("IOAccelerator"),
    &iterator
  )
  guard result == KERN_SUCCESS else {
    return defaultValue
  }
  defer { IOObjectRelease(iterator) }

  while case let entry = IOIteratorNext(iterator), entry != 0 {
    defer { IOObjectRelease(entry) }
    guard
      let performanceStatistics = ioAcceleratorPerformanceStatistics(for: entry),
      let utilization = ioAcceleratorDeviceUtilizationPercent(
        in: performanceStatistics
      )
    else {
      continue
    }
    return min(100, max(0, utilization))
  }

  return defaultValue
}

private func ioAcceleratorPerformanceStatistics(
  for entry: io_registry_entry_t
) -> CFDictionary? {
  guard
    let property = IORegistryEntryCreateCFProperty(
      entry,
      ioAcceleratorPerformanceStatisticsKey as CFString,
      kCFAllocatorDefault,
      0
    )?.takeRetainedValue(),
    CFGetTypeID(property) == CFDictionaryGetTypeID()
  else {
    return nil
  }

  return unsafeDowncast(property, to: CFDictionary.self)
}

private func ioAcceleratorDeviceUtilizationPercent(
  in performanceStatistics: CFDictionary
) -> Double? {
  let key = ioAcceleratorDeviceUtilizationKey as CFString
  var valuePointer: UnsafeRawPointer?
  // The raw pointer does not retain the bridged string used by the CF lookup.
  let found = withExtendedLifetime(key) {
    CFDictionaryGetValueIfPresent(
      performanceStatistics, Unmanaged.passUnretained(key).toOpaque(), &valuePointer
    )
  }
  guard
    found,
    let valuePointer
  else {
    return nil
  }

  let value = unsafeBitCast(valuePointer, to: AnyObject.self)
  guard CFGetTypeID(value) == CFNumberGetTypeID() else {
    return nil
  }

  let number = unsafeDowncast(value, to: CFNumber.self)
  var utilization: Double = 0
  guard CFNumberGetValue(number, .doubleType, &utilization) else {
    return nil
  }

  return utilization
}
