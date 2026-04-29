//
//  AgentSnapshotStore.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-29.
//  Copyright © 2026
//

import Foundation

enum AgentSnapshotStore {
    static func load(defaults: UserDefaults) -> AgentSnapshot? {
        guard
            let data = defaults.data(forKey: SharedConfigKeys.agentSnapshot),
            let snapshot = try? JSONDecoder().decode(AgentSnapshot.self, from: data),
            snapshot.schemaVersion == AgentSnapshot.currentSchemaVersion
        else { return nil }
        return snapshot
    }

    static func save(_ snapshot: AgentSnapshot, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: SharedConfigKeys.agentSnapshot)
    }

    static func clear(defaults: UserDefaults) {
        defaults.removeObject(forKey: SharedConfigKeys.agentSnapshot)
    }
}
