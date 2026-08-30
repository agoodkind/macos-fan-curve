//
//  SystemHelperArtifactValidator.swift
//  FanCurveAgent
//
//  Created by Alexander Goodkind <alex@goodkind.io> on 2026-08-04.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation
import SMCFanProtocol
import Security

private let systemHelperArtifactLog = AppLog.make(
  category: "SystemHelperArtifactValidator"
)

private enum SystemHelperArtifactConstants {
  static let bundleIdentifierKey = "CFBundleIdentifier"
  static let bundleVersionKey = "CFBundleVersion"
}

// MARK: - SystemHelperArtifactValidationError

enum SystemHelperArtifactValidationError: LocalizedError {
  case invalidMetadata(String)
  case missingExecutable
  case securityFailure(operation: String, status: OSStatus)

  var errorDescription: String? {
    switch self {
    case .invalidMetadata(let reason):
      return "System Helper metadata is invalid: \(reason)"
    case .missingExecutable:
      return "The bundled System Helper executable is missing"
    case let .securityFailure(operation, status):
      let description = SecCopyErrorMessageString(status, nil) as String?
      return "System Helper \(operation) failed: \(description ?? "status \(status)")"
    }
  }
}

// MARK: - SystemHelperArtifactValidating

protocol SystemHelperArtifactValidating: Sendable {
  func validate(at executableURL: URL) throws -> SystemHelperIdentity
}

// MARK: - SystemHelperArtifactValidator

struct SystemHelperArtifactValidator: SystemHelperArtifactValidating {
  private let commit: String
  private let expectedBuild: String
  private let expectedBundleIdentifier: String
  private let expectedTeamIdentifier: String
  private let expectedVersion: String

  init(
    expectedBundleIdentifier: String = generatedHelperBundleID,
    expectedTeamIdentifier: String = generatedDevelopmentTeam,
    expectedVersion: String = generatedMarketingVersion,
    expectedBuild: String = generatedBuildNumber,
    commit: String = generatedGitCommit
  ) {
    self.expectedBundleIdentifier = expectedBundleIdentifier
    self.expectedTeamIdentifier = expectedTeamIdentifier
    self.expectedVersion = expectedVersion
    self.expectedBuild = expectedBuild
    self.commit = commit
  }

  func validate(at executableURL: URL) throws -> SystemHelperIdentity {
    systemHelperArtifactLog.notice(
      "system_helper.preflight.started executable=\(executableURL.lastPathComponent, privacy: .public)"
    )
    guard executableURL.isFileURL,
      FileManager.default.fileExists(atPath: executableURL.path)
    else {
      systemHelperArtifactLog.error(
        "system_helper.preflight.failed stage=existence recovery=preserve-registration"
      )
      throw SystemHelperArtifactValidationError.missingExecutable
    }

    do {
      let code = try staticCode(for: executableURL)
      try validateSignature(code)
      let propertyList = try signingPropertyList(for: code)
      try validateMetadata(propertyList)
      let executableHash = try BuildFingerprint.hash(of: executableURL)
      let identity = SystemHelperIdentity(
        version: expectedVersion,
        build: expectedBuild,
        commit: commit,
        executableHash: executableHash,
        protocolVersion: SMCFanHelperProtocolVersion.identity
      )
      systemHelperArtifactLog.notice(
        "system_helper.preflight.completed version=\(expectedVersion, privacy: .public) build=\(expectedBuild, privacy: .public) hash=\(BuildFingerprint.presented(executableHash), privacy: .public)"
      )
      return identity
    } catch {
      systemHelperArtifactLog.error(
        "system_helper.preflight.failed stage=validation error=\(error.localizedDescription, privacy: .public) recovery=preserve-registration"
      )
      throw error
    }
  }

  private func staticCode(for executableURL: URL) throws -> SecStaticCode {
    var staticCode: SecStaticCode?
    let status = SecStaticCodeCreateWithPath(
      executableURL as CFURL,
      SecCSFlags(),
      &staticCode
    )
    guard status == errSecSuccess, let staticCode else {
      throw SystemHelperArtifactValidationError.securityFailure(
        operation: "code loading",
        status: status
      )
    }
    return staticCode
  }

  private func validateSignature(_ code: SecStaticCode) throws {
    let requirementText =
      "anchor apple generic and identifier \"\(expectedBundleIdentifier)\" "
      + "and certificate leaf[subject.OU] = \"\(expectedTeamIdentifier)\""
    var requirement: SecRequirement?
    let requirementStatus = SecRequirementCreateWithString(
      requirementText as CFString,
      SecCSFlags(),
      &requirement
    )
    guard requirementStatus == errSecSuccess, let requirement else {
      throw SystemHelperArtifactValidationError.securityFailure(
        operation: "requirement creation",
        status: requirementStatus
      )
    }
    let validationStatus = SecStaticCodeCheckValidity(
      code,
      SecCSFlags(rawValue: kSecCSStrictValidate),
      requirement
    )
    guard validationStatus == errSecSuccess else {
      throw SystemHelperArtifactValidationError.securityFailure(
        operation: "signature validation",
        status: validationStatus
      )
    }
  }

  private func signingPropertyList(
    for code: SecStaticCode
  ) throws -> NSDictionary {
    var signingInformation: CFDictionary?
    let status = SecCodeCopySigningInformation(
      code,
      SecCSFlags(rawValue: kSecCSSigningInformation),
      &signingInformation
    )
    guard status == errSecSuccess,
      let dictionary = signingInformation as NSDictionary?,
      let propertyList = dictionary.object(forKey: kSecCodeInfoPList) as? NSDictionary
    else {
      throw SystemHelperArtifactValidationError.securityFailure(
        operation: "metadata read",
        status: status
      )
    }
    return propertyList
  }

  private func validateMetadata(_ propertyList: NSDictionary) throws {
    try require(
      propertyList.object(forKey: SystemHelperArtifactConstants.bundleIdentifierKey)
        as? String,
      equals: expectedBundleIdentifier,
      field: "bundle identifier"
    )
    try require(
      propertyList.object(forKey: "CFBundleShortVersionString") as? String,
      equals: expectedVersion,
      field: "version"
    )
    try require(
      propertyList.object(forKey: SystemHelperArtifactConstants.bundleVersionKey)
        as? String,
      equals: expectedBuild,
      field: "build"
    )
  }

  private func require(
    _ actualValue: String?,
    equals expectedValue: String,
    field: String
  ) throws {
    guard actualValue == expectedValue else {
      throw SystemHelperArtifactValidationError.invalidMetadata(
        "\(field) does not match the generated configuration"
      )
    }
  }
}
