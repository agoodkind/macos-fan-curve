//
//  ContentView.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import SwiftUI

struct ContentView: View {
  @EnvironmentObject var xpcClient: XPCClient
  @State private var fanInfos: [String] = []
  @State private var errorMessage: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Circle()
          .fill(statusColor)
          .frame(width: 8, height: 8)
        Text(statusText)
          .font(.caption)
          .foregroundColor(.secondary)
      }

      if let error = errorMessage {
        Text(error)
          .foregroundColor(.red)
          .font(.caption)
      }

      ForEach(fanInfos, id: \.self) { info in
        Text(info)
          .font(.system(.body, design: .monospaced))
      }

      Button("Refresh") {
        Task { await refresh() }
      }

      Spacer()
    }
    .padding()
    .frame(minWidth: 500, minHeight: 300)
    .task { await refresh() }
  }

  private var statusColor: Color {
    switch xpcClient.state {
    case .connected: return .green
    case .disconnected: return .gray
    case .error: return .red
    }
  }

  private var statusText: String {
    switch xpcClient.state {
    case .connected: return "Connected to helper"
    case .disconnected: return "Disconnected"
    case .error(let msg): return "Error: \(msg)"
    }
  }

  private func refresh() async {
    do {
      let count = try await xpcClient.getFanCount()
      var infos: [String] = ["Fans: \(count)"]
      for i in 0..<count {
        let info = try await xpcClient.getFanInfo(i)
        infos.append(
          "Fan \(i): \(Int(info.actualRPM)) RPM (Target: \(Int(info.targetRPM)), Mode: \(info.manualMode ? "Manual" : "Auto"))"
        )
      }
      fanInfos = infos
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
