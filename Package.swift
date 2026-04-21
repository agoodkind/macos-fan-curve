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
    ],
    targets: [
        .target(
            name: "FanCurveModels",
            dependencies: [
                .product(name: "AppLog", package: "macos-smc-fan"),
            ],
            path: "Sources/Models",
            exclude: [
                // These files reference Xcode-generated constants or types
                // defined in other excluded files; they only compile via Xcode.
                "InstallationState.swift",
                "FanCurveModel.swift",
                "CurveLearner.swift",
                "LearnResultPublisher.swift",
            ],
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
