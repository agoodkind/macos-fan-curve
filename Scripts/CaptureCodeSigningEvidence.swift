#!/usr/bin/env swift

import Foundation
import Security

private struct SigningEvidenceError: Error, LocalizedError {
  let operation: String
  let status: OSStatus

  var errorDescription: String? {
    let detail = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
    return "\(operation) failed with status \(status): \(detail)"
  }
}

private func requireSuccess(
  _ status: OSStatus,
  operation: String
) throws {
  guard status == errSecSuccess else {
    throw SigningEvidenceError(operation: operation, status: status)
  }
}

private func signingEvidence(path: String) throws -> [String: Any] {
  let url = URL(fileURLWithPath: path).standardizedFileURL
  var staticCode: SecStaticCode?
  try requireSuccess(
    SecStaticCodeCreateWithPath(
      url as CFURL,
      SecCSFlags(),
      &staticCode
    ),
    operation: "SecStaticCodeCreateWithPath"
  )
  guard let staticCode else {
    throw SigningEvidenceError(
      operation: "SecStaticCodeCreateWithPath returned no code",
      status: errSecInternalComponent
    )
  }

  var signingInformation: CFDictionary?
  try requireSuccess(
    SecCodeCopySigningInformation(
      staticCode,
      SecCSFlags(rawValue: kSecCSSigningInformation),
      &signingInformation
    ),
    operation: "SecCodeCopySigningInformation"
  )
  let information = signingInformation as? [String: Any] ?? [:]

  var designatedRequirement: SecRequirement?
  try requireSuccess(
    SecCodeCopyDesignatedRequirement(
      staticCode,
      SecCSFlags(),
      &designatedRequirement
    ),
    operation: "SecCodeCopyDesignatedRequirement"
  )
  var requirementText: CFString?
  if let designatedRequirement {
    try requireSuccess(
      SecRequirementCopyString(
        designatedRequirement,
        SecCSFlags(),
        &requirementText
      ),
      operation: "SecRequirementCopyString"
    )
  }

  let certificates =
    information[kSecCodeInfoCertificates as String] as? [SecCertificate] ?? []
  let authorities = certificates.compactMap {
    SecCertificateCopySubjectSummary($0) as String?
  }
  let entitlements =
    information[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
  return [
    "path": url.path,
    "identifier": information[kSecCodeInfoIdentifier as String] as? String ?? "",
    "teamIdentifier":
      information[kSecCodeInfoTeamIdentifier as String] as? String ?? "",
    "authorities": authorities,
    "designatedRequirement": requirementText as String? ?? "",
    "entitlements": entitlements,
  ]
}

do {
  guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(
      Data("usage: CaptureCodeSigningEvidence.swift PATH\n".utf8)
    )
    exit(1)
  }
  let evidence = try signingEvidence(path: CommandLine.arguments[1])
  let data = try JSONSerialization.data(
    withJSONObject: evidence,
    options: [.prettyPrinted, .sortedKeys]
  )
  FileHandle.standardOutput.write(data)
  FileHandle.standardOutput.write(Data("\n".utf8))
} catch {
  FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
  exit(1)
}
