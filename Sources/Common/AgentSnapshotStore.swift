//
//  AgentSnapshotStore.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import Foundation

private let agentSnapshotStoreLog = AppLog.make(category: "AgentSnapshotStore")

enum AgentSnapshotStore {
    private struct SnapshotHeader: Decodable {
        let schemaVersion: Int
    }

    static func storedSchemaVersion(defaults: UserDefaults) -> Int? {
        guard let data = defaults.data(forKey: SharedConfigKeys.agentSnapshot) else { return nil }
        do {
            return try JSONDecoder().decode(SnapshotHeader.self, from: data).schemaVersion
        } catch {
            agentSnapshotStoreLog.notice(
                "snapshot.header_decode_failed error=\(error.localizedDescription, privacy: .public) recovery=treat-as-incompatible"
            )
            return nil
        }
    }

    static func save(_ snapshot: AgentSnapshot, defaults: UserDefaults) {
        let data: Data
        do {
            data = try JSONEncoder().encode(snapshot)
        } catch {
            agentSnapshotStoreLog.error(
                "snapshot.encode_failed error=\(error.localizedDescription, privacy: .public) recovery=skip-write"
            )
            return
        }
        defaults.set(data, forKey: SharedConfigKeys.agentSnapshot)
    }

    static func clear(defaults: UserDefaults) {
        defaults.removeObject(forKey: SharedConfigKeys.agentSnapshot)
    }
}
