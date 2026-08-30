//
//  TestControlBooleanObservation.swift
//  FanCurveAgentTests
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

import Foundation

// MARK: - TestControlBooleanObservation

final class TestControlBooleanObservation: @unchecked Sendable {
  private let lock = NSLock()
  private var storedValue = false

  var value: Bool {
    lock.lock()
    let observedValue = storedValue
    lock.unlock()
    return observedValue
  }

  func record() {
    lock.lock()
    storedValue = true
    lock.unlock()
  }
}
