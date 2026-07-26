//
//  TestControlSessionStore+Evidence.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-07-26.
//  Copyright © 2026, all rights reserved.
//

#if DEBUG
  import AppLog
  import Foundation

  extension TestControlSessionStore {
    func writeAcknowledgment(_ acknowledgment: TestControlAcknowledgment) throws {
      let participant = acknowledgment.participant
      try withExclusiveLock(fileName: TestControlFile.acknowledgmentLock(for: participant)) {
        let state = try loadState()
        try validateEnvelope(
          sessionID: acknowledgment.sessionID,
          revision: acknowledgment.revision,
          against: state
        )
        if let current = try loadAcknowledgment(for: participant),
          acknowledgment.revision < current.revision
        {
          throw TestControlError.revisionNotIncreasing(
            current: current.revision.value,
            proposed: acknowledgment.revision.value
          )
        }
        let url = acknowledgmentURL(for: participant)
        try writeAtomically(acknowledgment, to: url)
        testControlStoreLog.info(
          "test_control.ack.written participant=\(participant.rawValue, privacy: .public) session=\(acknowledgment.sessionID.uuidString, privacy: .public) revision=\(acknowledgment.revision.value, privacy: .public)"
        )
      }
    }

    func loadAcknowledgment(
      for participant: TestControlParticipant
    ) throws -> TestControlAcknowledgment? {
      let url = acknowledgmentURL(for: participant)
      guard FileManager.default.fileExists(atPath: url.path) else {
        return nil
      }
      do {
        let data = try Data(contentsOf: url)
        let acknowledgment = try TestControlCodec.decode(
          TestControlAcknowledgment.self,
          from: data
        )
        guard acknowledgment.participant == participant else {
          throw TestControlError.acknowledgmentParticipantMismatch(
            expected: participant,
            actual: acknowledgment.participant
          )
        }
        let state = try loadState()
        try validateEnvelope(
          sessionID: acknowledgment.sessionID,
          revision: acknowledgment.revision,
          against: state
        )
        return acknowledgment
      } catch {
        testControlStoreLog.error(
          "test_control.ack.load_failed participant=\(participant.rawValue, privacy: .public) path=\(url.path, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=reject-acknowledgment"
        )
        throw error
      }
    }

    func appendEvent(_ event: TestControlEvent) throws {
      try withExclusiveLock(fileName: TestControlFile.eventsLock(for: event.participant)) {
        let state = try loadState()
        try validateEnvelope(
          sessionID: event.sessionID,
          revision: event.revision,
          against: state
        )
        let existingEvents = try loadEvents(for: event.participant)
        if let current = existingEvents.last, event.revision < current.revision {
          throw TestControlError.revisionNotIncreasing(
            current: current.revision.value,
            proposed: event.revision.value
          )
        }
        var data = try TestControlCodec.encode(event)
        data.append(TestControlJSONLines.delimiter)
        try append(data, to: eventsURL(for: event.participant))
        testControlStoreLog.info(
          "test_control.event.appended participant=\(event.participant.rawValue, privacy: .public) kind=\(event.kind.rawValue, privacy: .public) session=\(event.sessionID.uuidString, privacy: .public) revision=\(event.revision.value, privacy: .public)"
        )
      }
    }

    func loadEvents(for participant: TestControlParticipant) throws -> [TestControlEvent] {
      let url = eventsURL(for: participant)
      guard FileManager.default.fileExists(atPath: url.path) else {
        return []
      }
      do {
        let data = try Data(contentsOf: url)
        let lines = data.split(separator: TestControlJSONLines.delimiter)
        let state = try loadState()
        var events: [TestControlEvent] = []
        var lastRevision: TestControlRevision?
        for line in lines {
          let event = try TestControlCodec.decode(TestControlEvent.self, from: Data(line))
          guard event.participant == participant else {
            throw TestControlError.acknowledgmentParticipantMismatch(
              expected: participant,
              actual: event.participant
            )
          }
          try validateEnvelope(
            sessionID: event.sessionID,
            revision: event.revision,
            against: state
          )
          if let lastRevision, event.revision < lastRevision {
            throw TestControlError.revisionNotIncreasing(
              current: lastRevision.value,
              proposed: event.revision.value
            )
          }
          events.append(event)
          lastRevision = event.revision
        }
        return events
      } catch {
        testControlStoreLog.error(
          "test_control.events.load_failed participant=\(participant.rawValue, privacy: .public) path=\(url.path, privacy: .public) error=\(error.localizedDescription, privacy: .public) recovery=reject-evidence"
        )
        throw error
      }
    }

    func exportEvidence(to destination: URL) throws {
      testControlStoreLog.info(
        "test_control.evidence.export.started source=\(directory.path, privacy: .public) destination=\(destination.path, privacy: .public)"
      )
      try Self.createSessionDirectory(at: destination)
      let contents = try FileManager.default.contentsOfDirectory(
        at: destination,
        includingPropertiesForKeys: nil
      )
      guard contents.isEmpty else {
        throw TestControlError.evidenceDestinationNotEmpty(destination.path)
      }
      for fileName in TestControlFile.evidenceFiles {
        let source = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: source.path) else {
          continue
        }
        try FileManager.default.copyItem(
          at: source,
          to: destination.appendingPathComponent(fileName)
        )
      }
      testControlStoreLog.info(
        "test_control.evidence.export.completed destination=\(destination.path, privacy: .public)"
      )
    }
  }
#endif
