//
//  main.swift
//  SMCFanHelper
//
//  Created by Alex Goodkind <alex@goodkind.io> on 2026-06-08.
//  Copyright © 2026, all rights reserved.
//

import AppLog
import SMCFanHelperCore

// The daemon logic lives in SMCFanHelperCore; the __info_plist and
// __launchd_plist sections are linked via -sectcreate in the target settings.
BuildInfo.version = generatedMarketingVersion
BuildInfo.build = generatedBuildNumber
BuildInfo.commit = generatedGitCommit
BuildInfo.dirty = generatedGitDirty
AppLog.bootstrap(subsystem: "io.goodkind.fan")
SMCFanHelper(machServiceName: generatedHelperBundleID).start()
