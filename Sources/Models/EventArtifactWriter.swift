//
//  EventArtifactWriter.swift
//  FanCurveAgent
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-18.
//  Copyright © 2026
//

import AppLog
import Foundation

private let log = AppLog.make(category: "EventArtifactWriter")

/// Append-only NDJSON ring of agent tick events. Future GUI history view
/// reads this file directly. Two-file cap: when events.jsonl crosses the
/// 50 MB threshold it is renamed to events.1.jsonl (overwriting any prior
/// rotation) and a fresh events.jsonl is started.
///
/// Lives in ~/Library/Application Support/io.goodkind.fan/. The directory
/// is created with 0o700 so other users on the box cannot read tick data.
final class EventArtifactWriter: @unchecked Sendable {
  struct Event: Codable, Sendable {
    let ts: Date
    let kind: String
    let fanRPM: [Float]
    let tempC: Double
    let curvePoint: Double
  }

  private let lock = NSLock()
  private let directory: URL
  private let active: URL
  private let rotated: URL
  private let rotateThreshold: Int = 50 * 1024 * 1024
  private let encoder: JSONEncoder

  init() {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    self.directory = support.appendingPathComponent("io.goodkind.fan", isDirectory: true)
    self.active = directory.appendingPathComponent("events.jsonl")
    self.rotated = directory.appendingPathComponent("events.1.jsonl")

    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601
    self.encoder = enc

    ensureDirectory()
  }

  func append(kind: String, fanRPM: [Float], tempC: Double, curvePoint: Double) {
    let event = Event(ts: Date(), kind: kind, fanRPM: fanRPM, tempC: tempC, curvePoint: curvePoint)
    do {
      var data = try encoder.encode(event)
      data.append(0x0A)

      lock.lock()
      defer { lock.unlock() }

      rotateIfNeededLocked()
      try writeLocked(data)
      log.info("event.recorded kind=\(kind, privacy: .public)")
    } catch {
      log.error("event.write.failed kind=\(kind, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
    }
  }

  private func ensureDirectory() {
    let fm = FileManager.default
    do {
      try fm.createDirectory(
        at: directory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
    } catch {
      log.error("artifact.dir.failed path=\(directory.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
    }
  }

  private func rotateIfNeededLocked() {
    let attrs = try? FileManager.default.attributesOfItem(atPath: active.path)
    guard let size = attrs?[.size] as? Int, size >= rotateThreshold else { return }
    let fm = FileManager.default
    try? fm.removeItem(at: rotated)
    do {
      try fm.moveItem(at: active, to: rotated)
      log.notice("artifact.rotated from=\(active.lastPathComponent, privacy: .public) to=\(rotated.lastPathComponent, privacy: .public)")
    } catch {
      log.error("artifact.rotate.failed error=\(error.localizedDescription, privacy: .public)")
    }
  }

  private func writeLocked(_ data: Data) throws {
    let fm = FileManager.default
    if !fm.fileExists(atPath: active.path) {
      fm.createFile(atPath: active.path, contents: data, attributes: [.posixPermissions: 0o600])
      log.info("artifact.written path=\(active.path, privacy: .public) kind=create")
      return
    }
    let handle = try FileHandle(forWritingTo: active)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
  }
}
