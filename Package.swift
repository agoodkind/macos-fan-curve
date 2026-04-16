// swift-tools-version: 6.0
//
//  Package.swift
//  FanCurve
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-04-15.
//  Copyright © 2026
//

import PackageDescription

let package = Package(
    name: "FanCurve",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/agoodkind/macos-smc-fan.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
        .package(url: "https://github.com/xcode-actions/json-logger.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "FanCurveModels",
            path: "Sources/Models",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "ModelTests",
            dependencies: ["FanCurveModels"],
            path: "Tests/ModelTests",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
    ]
)
