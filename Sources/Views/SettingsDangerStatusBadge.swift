//
//  SettingsDangerStatusBadge.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-05-24.
//  Copyright © 2026
//

import SwiftUI

struct SettingsDangerStatusBadge: View {
    let status: String

    var body: some View {
        Label {
            Text(status)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color(nsColor: .systemOrange))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}
