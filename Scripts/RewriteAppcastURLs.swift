#!/usr/bin/env swift

import Foundation

struct Failure: Error, CustomStringConvertible {
  let description: String
}

func requiredArgument(_ name: String, arguments: [String]) throws -> String {
  guard let index = arguments.firstIndex(of: name) else {
    throw Failure(description: "RewriteAppcastURLs: missing \(name)")
  }
  let valueIndex = arguments.index(after: index)
  guard valueIndex < arguments.endIndex else {
    throw Failure(description: "RewriteAppcastURLs: missing value for \(name)")
  }
  return arguments[valueIndex]
}

func assetTags(from mappingURL: URL) throws -> [String: String] {
  let contents = try String(contentsOf: mappingURL, encoding: .utf8)
  var result: [String: String] = [:]

  for line in contents.split(whereSeparator: \.isNewline) {
    let fields = line.split(separator: "\t", maxSplits: 1).map(String.init)
    guard fields.count == 2 else {
      throw Failure(
        description: "RewriteAppcastURLs: invalid mapping line \(line)"
      )
    }
    let releaseTag = fields[0]
    let assetName = fields[1]
    guard result[assetName] == nil else {
      throw Failure(
        description: "RewriteAppcastURLs: duplicate asset mapping for \(assetName)"
      )
    }
    result[assetName] = releaseTag
  }

  guard !result.isEmpty else {
    throw Failure(description: "RewriteAppcastURLs: mapping is empty")
  }
  return result
}

func encodedPathComponent(_ value: String) throws -> String {
  guard
    let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
  else {
    throw Failure(description: "RewriteAppcastURLs: could not encode \(value)")
  }
  return encoded
}

func releaseAssetURL(
  repository: String,
  releaseTag: String,
  assetName: String
) throws -> String {
  let repositoryParts = repository.split(separator: "/", omittingEmptySubsequences: false)
  guard repositoryParts.count == 2 else {
    throw Failure(
      description: "RewriteAppcastURLs: repository must use owner/name"
    )
  }

  let owner = try encodedPathComponent(String(repositoryParts[0]))
  let name = try encodedPathComponent(String(repositoryParts[1]))
  let tag = try encodedPathComponent(releaseTag)
  let asset = try encodedPathComponent(assetName)
  return "https://github.com/\(owner)/\(name)/releases/download/\(tag)/\(asset)"
}

func rewriteAppcast(
  appcastURL: URL,
  mappingURL: URL,
  repository: String
) throws {
  let mapping = try assetTags(from: mappingURL)
  let document = try XMLDocument(
    contentsOf: appcastURL,
    options: [.nodePreserveAll]
  )
  let enclosureNodes = try document.nodes(forXPath: "//*[local-name()='enclosure']")
  guard !enclosureNodes.isEmpty else {
    throw Failure(description: "RewriteAppcastURLs: appcast has no enclosures")
  }

  var rewrittenAssets = Set<String>()
  for node in enclosureNodes {
    guard
      let enclosure = node as? XMLElement,
      let urlAttribute = enclosure.attribute(forName: "url"),
      let urlValue = urlAttribute.stringValue,
      let assetName = URL(string: urlValue)?.lastPathComponent.removingPercentEncoding,
      let releaseTag = mapping[assetName]
    else {
      throw Failure(
        description: "RewriteAppcastURLs: enclosure URL has no release mapping"
      )
    }

    urlAttribute.stringValue = try releaseAssetURL(
      repository: repository,
      releaseTag: releaseTag,
      assetName: assetName
    )
    rewrittenAssets.insert(assetName)
  }

  let missingAssets = Set(mapping.keys).subtracting(rewrittenAssets)
  guard missingAssets.isEmpty else {
    let assetList = missingAssets.sorted().joined(separator: ", ")
    throw Failure(
      description: "RewriteAppcastURLs: appcast omitted mapped assets: \(assetList)"
    )
  }

  try document.xmlData(options: [.nodePrettyPrint]).write(
    to: appcastURL,
    options: [.atomic]
  )
}

do {
  let arguments = Array(CommandLine.arguments.dropFirst())
  let appcastPath = try requiredArgument("--appcast", arguments: arguments)
  let mappingPath = try requiredArgument("--mapping", arguments: arguments)
  let repository = try requiredArgument("--repository", arguments: arguments)
  try rewriteAppcast(
    appcastURL: URL(fileURLWithPath: appcastPath),
    mappingURL: URL(fileURLWithPath: mappingPath),
    repository: repository
  )
} catch {
  FileHandle.standardError.write(Data("\(error)\n".utf8))
  exit(1)
}
