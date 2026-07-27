//
//  SensorKeyResolver.swift
//  FanCurveAgent
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-27.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

private let log = AppLog.make(category: "SensorKeyResolution")

private enum SensorKeyResolutionConstants {
  /// Cap on how many discovered keys the loud fallback log line lists.
  /// Real hardware reports hundreds of SMC keys; the log line stays
  /// scannable while still carrying enough of the list to diagnose a
  /// catalog mismatch.
  static let diagnosticKeySampleLimit = 40
}

/// Discovers the SMC keys actually present on this machine. The agent's
/// `FanHardware` port refines this protocol, so the same injected hardware
/// seam answers discovery. Declared separately here so resolution stays
/// independent of the agent-layer port and tests can substitute a fake
/// without a privileged helper.
public protocol SMCKeyDiscovering: Sendable {
  func enumerateKeys() async -> [String]
}

/// Why resolution fell back to probing the full catalog instead of the
/// keys the SMC intersection actually left.
public enum SensorKeyFallbackReason: Sendable, Equatable, CustomStringConvertible {
  /// `enumerateKeys()` returned no keys. That is indistinguishable from a
  /// helper outage, so it is never treated as "this machine has zero
  /// keys" and never prunes.
  case enumerationUnavailable
  /// Enumeration succeeded, but no catalog CPU temperature key survived
  /// the intersection. Controlling nothing would leave `maxCPUTemp` at 0
  /// forever, so the full catalog is probed instead.
  case noCPUKeySurvived

  public var description: String {
    switch self {
    case .enumerationUnavailable: return "enumeration_unavailable"
    case .noCPUKeySurvived: return "no_cpu_key_survived"
    }
  }
}

/// Effective sensor key set for a single agent process lifetime, resolved
/// once at startup against the keys the SMC actually reports.
public struct ResolvedSensorKeys: Sendable, Equatable {
  public let tempKeys: [String]
  public let cpuTempKeys: Set<String>
  public let excludedKeys: [String]
  public let usedFallback: Bool
  public let fallbackReason: SensorKeyFallbackReason?

  public init(
    tempKeys: [String],
    cpuTempKeys: Set<String>,
    excludedKeys: [String],
    usedFallback: Bool,
    fallbackReason: SensorKeyFallbackReason?
  ) {
    self.tempKeys = tempKeys
    self.cpuTempKeys = cpuTempKeys
    self.excludedKeys = excludedKeys
    self.usedFallback = usedFallback
    self.fallbackReason = fallbackReason
  }
}

/// Resolves the catalog's guessed key set against what the SMC actually
/// reports, once per agent process lifetime.
///
/// Only prunes a catalog key when its absence from `enumerateKeys()` is a
/// definite answer. An empty discovery result is ambiguous between "helper
/// unreachable" and "this machine truly has no keys," so it is always
/// treated as the former and never prunes.
public enum SensorKeyResolver {
  public static func resolve(
    catalogTempKeys: [String],
    catalogCPUTempKeys: Set<String>,
    discoveredKeys: [String]
  ) -> ResolvedSensorKeys {
    guard !discoveredKeys.isEmpty else {
      log.error(
        "agent.sensors.fallback reason=\(SensorKeyFallbackReason.enumerationUnavailable.description, privacy: .public) discoveredCount=0 recovery=probe-full-catalog"
      )
      return ResolvedSensorKeys(
        tempKeys: catalogTempKeys,
        cpuTempKeys: catalogCPUTempKeys,
        excludedKeys: [],
        usedFallback: true,
        fallbackReason: .enumerationUnavailable
      )
    }

    let discovered = Set(discoveredKeys)
    let survivingTempKeys = catalogTempKeys.filter { discovered.contains($0) }
    let excludedKeys = catalogTempKeys.filter { !discovered.contains($0) }
    let survivingCPUKeys = catalogCPUTempKeys.filter { discovered.contains($0) }

    guard !survivingCPUKeys.isEmpty else {
      let sample =
        discoveredKeys
        .sorted()
        .prefix(SensorKeyResolutionConstants.diagnosticKeySampleLimit)
        .joined(separator: ",")
      log.error(
        "agent.sensors.fallback reason=\(SensorKeyFallbackReason.noCPUKeySurvived.description, privacy: .public) discoveredCount=\(discoveredKeys.count, privacy: .public) discoveredSample=\(sample, privacy: .public) recovery=probe-full-catalog"
      )
      return ResolvedSensorKeys(
        tempKeys: catalogTempKeys,
        cpuTempKeys: catalogCPUTempKeys,
        excludedKeys: [],
        usedFallback: true,
        fallbackReason: .noCPUKeySurvived
      )
    }

    log.notice(
      "agent.sensors.resolved count=\(survivingTempKeys.count, privacy: .public) keys=\(survivingTempKeys.joined(separator: ","), privacy: .public)"
    )
    log.notice(
      "agent.sensors.excluded count=\(excludedKeys.count, privacy: .public) keys=\(excludedKeys.joined(separator: ","), privacy: .public)"
    )

    return ResolvedSensorKeys(
      tempKeys: survivingTempKeys,
      cpuTempKeys: survivingCPUKeys,
      excludedKeys: excludedKeys,
      usedFallback: false,
      fallbackReason: nil
    )
  }

  /// Discovers the machine's real key set through `discoverer` and resolves
  /// it against the catalog. Isolated behind `SMCKeyDiscovering` so tests
  /// can exercise this async boundary with a fake instead of the real XPC
  /// client, which needs a privileged helper.
  public static func resolve(
    catalogTempKeys: [String],
    catalogCPUTempKeys: Set<String>,
    discoverer: SMCKeyDiscovering
  ) async -> ResolvedSensorKeys {
    let discoveredKeys = await discoverer.enumerateKeys()
    return resolve(
      catalogTempKeys: catalogTempKeys,
      catalogCPUTempKeys: catalogCPUTempKeys,
      discoveredKeys: discoveredKeys
    )
  }
}
