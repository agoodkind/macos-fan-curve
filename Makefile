-include Config/local.xcconfig

CONFIGURATION = Release
BUILD_DIR = build
PRODUCTS_DIR = Products
CODE_SIGN_IDENTITY ?= Developer ID Application
DEVELOPMENT_TEAM ?= H3BMXM4W7H
BUNDLE_ID_PREFIX ?= io.goodkind
SWIFT_FORMAT_FILES = Sources Tests Project.swift Tuist.swift Tuist/Package.swift $(wildcard Workspace.swift)
ANALYZE_BUILD_DIR = $(BUILD_DIR)/Analyze
SWIFTLINT_ANALYZE_DERIVED_DATA = $(ANALYZE_BUILD_DIR)/SwiftLintDerivedData
SWIFTLINT_ANALYZE_LOG = $(ANALYZE_BUILD_DIR)/swiftlint-xcodebuild.log
APP_NAME = FanCurve
AGENT_EXECUTABLE_NAME = FanCurveAgent
APP_DISPLAY_NAME = Fan Curve
APP_BUNDLE_NAME = $(APP_DISPLAY_NAME)
AGENT_DISPLAY_NAME = Fan Curve Background Control
HELPER_DISPLAY_NAME = Fan Curve Hardware Helper
HELPER_BUNDLE_ID ?= $(BUNDLE_ID_PREFIX).smcfanhelper
APP_BUNDLE_ID ?= $(BUNDLE_ID_PREFIX).fancurve
AGENT_BUNDLE_ID ?= $(BUNDLE_ID_PREFIX).fancurveagent
SHARED_SUITE_ID ?= $(BUNDLE_ID_PREFIX).fancurve.shared
DMG_NAME = $(APP_NAME)-$(CONFIGURATION)
MARKETING_VERSION ?= 0.1.0
CURRENT_PROJECT_VERSION ?= 1
SPARKLE_FEED_URL ?= https://goodkind.io/fancurve/appcast.xml
# Sparkle's Ed25519 PUBLIC key: shipped in every released Info.plist already,
# so it is committed here and CI needs no secret for it.
SPARKLE_PUBLIC_ED_KEY ?= dYrjw1tlOKpU4dRh8DL3k4u+xIl42Zkio09nZOOS6No=  # gitleaks:allow
RELEASE_TAG ?= $(CURRENT_PROJECT_VERSION)-$(shell git rev-parse --short HEAD)
# The DMG signs with the same identity as the app unless overridden.
DMG_SIGN_IDENTITY ?= $(CODE_SIGN_IDENTITY)
DMG_VOLUME_NAME = $(APP_DISPLAY_NAME)
DMG_STAGING_DIR = $(BUILD_DIR)/dmg
XCODE_PRODUCTS_DIR = $(BUILD_DIR)/Build/Products/$(CONFIGURATION)
APP_SOURCE = $(XCODE_PRODUCTS_DIR)/$(APP_BUNDLE_NAME).app
APP_DEST = $(PRODUCTS_DIR)/$(APP_BUNDLE_NAME).app
LEGACY_APP_DEST = $(PRODUCTS_DIR)/$(APP_NAME).app
INSTALL_APP_DEST ?= /Applications/$(APP_BUNDLE_NAME).app
AGENT_LABEL ?= io.goodkind.fancurveagent
AGENT_PLIST_NAME ?= agent-launchd.plist
AGENT_BUNDLED_PLIST ?= $(APP_DEST)/Contents/Library/LaunchAgents/$(AGENT_PLIST_NAME)
AGENT_BUNDLE_PROGRAM = Contents/MacOS/FanCurveAgent
ICON_HASH_STAMP = $(BUILD_DIR)/.app-icon.sha
DMG_PATH = $(PRODUCTS_DIR)/$(DMG_NAME).dmg
RELEASE_DMG_NAME = $(APP_NAME)-$(CURRENT_PROJECT_VERSION).dmg
RELEASE_DMG_PATH = $(PRODUCTS_DIR)/$(RELEASE_DMG_NAME)
SPARKLE_UPDATES_DIR = $(BUILD_DIR)/sparkle-updates
SPARKLE_APPCAST_PATH = $(SPARKLE_UPDATES_DIR)/appcast.xml
GITHUB_RELEASE_BASE_URL ?= https://github.com/agoodkind/macos-fan-curve/releases/download/$(RELEASE_TAG)/
GENERATE_CONFIG_ENV = SRCROOT="$(CURDIR)" HELPER_BUNDLE_ID="$(HELPER_BUNDLE_ID)" HELPER_DISPLAY_NAME="$(HELPER_DISPLAY_NAME)" APP_BUNDLE_ID="$(APP_BUNDLE_ID)" APP_DISPLAY_NAME="$(APP_DISPLAY_NAME)" AGENT_BUNDLE_ID="$(AGENT_BUNDLE_ID)" AGENT_DISPLAY_NAME="$(AGENT_DISPLAY_NAME)" AGENT_EXECUTABLE_NAME="$(AGENT_EXECUTABLE_NAME)" SHARED_SUITE_ID="$(SHARED_SUITE_ID)" DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)" BUNDLE_ID_PREFIX="$(BUNDLE_ID_PREFIX)" SPARKLE_FEED_URL="$(SPARKLE_FEED_URL)" SPARKLE_PUBLIC_ED_KEY="$(SPARKLE_PUBLIC_ED_KEY)"
# Signing is owned by swift-mk (XCODE_XCCONFIG_FILE override), not set here.
XCODE_BUILD_SETTINGS = BUNDLE_ID_PREFIX="$(BUNDLE_ID_PREFIX)" HELPER_BUNDLE_ID="$(HELPER_BUNDLE_ID)" APP_BUNDLE_ID="$(APP_BUNDLE_ID)" AGENT_BUNDLE_ID="$(AGENT_BUNDLE_ID)" SHARED_SUITE_ID="$(SHARED_SUITE_ID)" HELPER_DISPLAY_NAME="$(HELPER_DISPLAY_NAME)" APP_DISPLAY_NAME="$(APP_DISPLAY_NAME)" AGENT_DISPLAY_NAME="$(AGENT_DISPLAY_NAME)" AGENT_EXECUTABLE_NAME="$(AGENT_EXECUTABLE_NAME)" SPARKLE_FEED_URL="$(SPARKLE_FEED_URL)" SPARKLE_PUBLIC_ED_KEY="$(SPARKLE_PUBLIC_ED_KEY)"

SWIFT_MK_MODULES := swift-build.mk swift-release.mk
# This project defines its own `run` (Debug build deployed to /Applications). The
# swift-build.mk module skips its generic `run` when this is set, avoiding a Make
# "overriding commands" warning. Takes effect once the guard is synced into .make/.
SWIFT_MK_OWN_RUN := 1
SWIFT_BUILD_CMD := $(MAKE) SWIFT_MK_SKIP_FETCH=1 app-local
# Release artifacts for the shared _release.yml pipeline: the signed DMG into
# dist/. MARKETING_VERSION/CURRENT_PROJECT_VERSION/RELEASE_TAG arrive as env
# from the workflow's release-meta job; the ?= declarations above pick them up.
SWIFT_MK_RELEASE_BUILD_CMD := $(MAKE) SWIFT_MK_SKIP_FETCH=1 release-assets && cp "$(RELEASE_DMG_PATH)" dist/
# The project-build recipe writes its index store under BUILD_DIR, so the
# dead-code gate reads from there. A clean build before the scan keeps the index
# free of stale units from earlier incremental builds.
SWIFT_MK_DERIVED_DATA := $(BUILD_DIR)
SWIFT_DEADCODE_BUILD_CMD := rm -rf "$(BUILD_DIR)" && $(MAKE) SWIFT_MK_SKIP_FETCH=1 CONFIGURATION=Debug app-local
SWIFT_TEST_CMD := $(MAKE) SWIFT_MK_SKIP_FETCH=1 test-local
SWIFT_GENERATE_CMD := $(MAKE) SWIFT_MK_SKIP_FETCH=1 generate-project
SWIFT_CLEAN_CMD := rm -rf $(BUILD_DIR) $(PRODUCTS_DIR) FanCurveApp.xcworkspace FanCurveApp.xcodeproj
SWIFT_ANALYZE_CMD := $(MAKE) SWIFT_MK_SKIP_FETCH=1 xcode-analyze swiftlint-analyze
SWIFT_LOG_AUDIT_CMD := Scripts/AuditLogging.swift Sources
SWIFT_FORMAT_TARGETS := $(SWIFT_FORMAT_FILES)
SWIFTLINT_TARGETS := $(SWIFT_FORMAT_FILES)
SWIFTCHECK_EXTRA_TARGETS := $(SWIFT_FORMAT_FILES)

# Generator names are data, bound to variables so no recipe line names a build
# tool directly; every build/test/analyze routes through the swift-mk toolchain.
FANCURVE_GENERATOR := tuist

include bootstrap.mk

.PHONY: all install-dependencies install-analysis-tools app app-local run project-build install-app dmg release-assets prepare-sparkle-updates sparkle-appcast appcast generate-project generate-config-artifacts open-project test-local format format-check swiftlint-lint xcode-analyze swiftlint-analyze periphery-scan launch-agent-audit run-audit settings-layout-audit verify quality icons

all: app

install-dependencies: swift-mk-bin
	"$(SWIFT_MK_BIN)" toolchain install --generator $(FANCURVE_GENERATOR)

install-analysis-tools: lint-tools

generate-config-artifacts:
	@TARGET_NAME="$(APP_NAME)" $(GENERATE_CONFIG_ENV) ./Scripts/GenerateConfig.swift
	@TARGET_NAME="$(AGENT_EXECUTABLE_NAME)" $(GENERATE_CONFIG_ENV) ./Scripts/GenerateConfig.swift

generate-project: swift-mk-bin generate-config-artifacts
	"$(SWIFT_MK_BIN)" toolchain generate --generator $(FANCURVE_GENERATOR)

lint-deadcode: generate-project

open-project: generate-project
	open FanCurveApp.xcworkspace

icons:
	./Scripts/GenerateIcons.swift

project-build: generate-config-artifacts icons generate-project
	"$(SWIFT_MK_BIN)" toolchain build \
		--generator $(FANCURVE_GENERATOR) \
		--workspace FanCurveApp.xcworkspace \
		--scheme FanCurve \
		--configuration $(CONFIGURATION) \
		--derived-data-path $(BUILD_DIR) \
		$(XCODE_BUILD_SETTINGS) \
		$(SWIFT_MK_XCODEBUILD_ARGS) \
		MARKETING_VERSION="$(MARKETING_VERSION)" \
		CURRENT_PROJECT_VERSION="$(CURRENT_PROJECT_VERSION)"

app-local: project-build
	@mkdir -p $(PRODUCTS_DIR)
	@./Scripts/RefreshIconCache.swift "$(APP_SOURCE)" "$(ICON_HASH_STAMP)"
	@rm -rf "$(APP_DEST)" "$(LEGACY_APP_DEST)"
	@cp -R "$(APP_SOURCE)" "$(PRODUCTS_DIR)/"
	@./Scripts/RefreshIconCache.swift "$(APP_DEST)" "$(ICON_HASH_STAMP)"

app: build

# Build the Debug app, deploy it to /Applications, and launch it.
# /Applications/Fan Curve.app is the single canonical location the SMAppService daemon
# and login-item agent register from. Xcode builds to DerivedData and the Play button
# runs that copy for debugging; the canonical install lives at /Applications. The dev
# state-simulation menu and the FANCURVE_DEV_SCENARIO flag are compiled only into Debug
# builds, so this is also the simulated-state path.
run:
	$(MAKE) SWIFT_MK_SKIP_FETCH=1 CONFIGURATION=Debug app-local
	@rm -rf "$(INSTALL_APP_DEST)"
	@cp -R "$(APP_DEST)" "$(INSTALL_APP_DEST)"
	@Scripts/TerminateAppInstances.swift "$(APP_BUNDLE_ID)"
	@open "$(INSTALL_APP_DEST)"

# Install the Release build to the canonical /Applications location.
install-app: app
	@rm -rf "$(INSTALL_APP_DEST)"
	@cp -R "$(APP_DEST)" "$(INSTALL_APP_DEST)"

dmg: app
	@mkdir -p "$(PRODUCTS_DIR)"
	@rm -rf "$(DMG_STAGING_DIR)" "$(DMG_PATH)"
	@mkdir -p "$(DMG_STAGING_DIR)"
	@cp -R "$(APP_DEST)" "$(DMG_STAGING_DIR)/"
	@ln -s /Applications "$(DMG_STAGING_DIR)/Applications"
	@staged_count="$$(find "$(DMG_STAGING_DIR)" -maxdepth 1 -name '*.app' | wc -l | tr -d ' ')"; \
	if [ "$$staged_count" != "1" ] || [ ! -d "$(DMG_STAGING_DIR)/$(APP_BUNDLE_NAME).app" ]; then \
		echo "dmg staging error: expected exactly one app bundle ($(APP_BUNDLE_NAME).app) in $(DMG_STAGING_DIR), found $$staged_count:"; \
		find "$(DMG_STAGING_DIR)" -maxdepth 1 -name '*.app'; \
		exit 1; \
	fi
	hdiutil create -volname "$(DMG_VOLUME_NAME)" \
		-srcfolder "$(DMG_STAGING_DIR)" \
		-fs HFS+ \
		-format UDZO \
		-ov "$(DMG_PATH)"
	@if [ -n "$(DMG_SIGN_IDENTITY)" ]; then \
		codesign --force --sign "$(DMG_SIGN_IDENTITY)" "$(DMG_PATH)"; \
	fi

release-assets: dmg
	@cp "$(DMG_PATH)" "$(RELEASE_DMG_PATH)"

prepare-sparkle-updates:
	@test -f "$(RELEASE_DMG_PATH)"
	@rm -rf "$(SPARKLE_UPDATES_DIR)"
	@mkdir -p "$(SPARKLE_UPDATES_DIR)"
	@cp "$(RELEASE_DMG_PATH)" "$(SPARKLE_UPDATES_DIR)/"
	@SPARKLE_APPCAST_TOOL="$$(Scripts/FindSparkleTool.swift "$(BUILD_DIR)" generate_appcast)"; \
	if [ -n "$${SPARKLE_PRIVATE_KEY_FILE:-}" ]; then \
		"$${SPARKLE_APPCAST_TOOL}" \
			--ed-key-file "$${SPARKLE_PRIVATE_KEY_FILE}" \
			--download-url-prefix "$(GITHUB_RELEASE_BASE_URL)" \
			"$(SPARKLE_UPDATES_DIR)"; \
	else \
		"$${SPARKLE_APPCAST_TOOL}" \
			--download-url-prefix "$(GITHUB_RELEASE_BASE_URL)" \
			"$(SPARKLE_UPDATES_DIR)"; \
	fi

sparkle-appcast: release-assets prepare-sparkle-updates

# Regenerate the appcast for an already-published release: download its DMG,
# derive the build version from the asset name, and run the Sparkle generator.
# RELEASE_TAG names the release; SPARKLE_PRIVATE_KEY_FILE (optional) signs.
appcast:
	@if [ -z "$(strip $(RELEASE_TAG))" ]; then echo "appcast: RELEASE_TAG is required"; exit 1; fi
	@mkdir -p $(PRODUCTS_DIR)
	gh release download "$(RELEASE_TAG)" --pattern "$(APP_NAME)-*.dmg" --dir $(PRODUCTS_DIR) --clobber
	@dmg="$$(ls $(PRODUCTS_DIR)/$(APP_NAME)-*.dmg | sed -n 1p)"; \
	build_version="$$(basename "$$dmg" .dmg | sed 's/^$(APP_NAME)-//')"; \
	$(MAKE) SWIFT_MK_SKIP_FETCH=1 prepare-sparkle-updates \
		CURRENT_PROJECT_VERSION="$$build_version" \
		RELEASE_TAG="$(RELEASE_TAG)"

test-local: generate-config-artifacts generate-project
	"$(SWIFT_MK_BIN)" toolchain test \
		--generator $(FANCURVE_GENERATOR) \
		--workspace FanCurveApp.xcworkspace \
		--scheme FanCurve \
		--configuration Debug \
		--derived-data-path $(BUILD_DIR) \
		$(XCODE_BUILD_SETTINGS) \
		$(SWIFT_MK_XCODEBUILD_ARGS)

format: fmt

format-check: lint-format

swiftlint-lint: lint-swiftlint

xcode-analyze: generate-project
	"$(SWIFT_MK_BIN)" toolchain analyze \
		--generator $(FANCURVE_GENERATOR) \
		--workspace FanCurveApp.xcworkspace \
		--scheme FanCurve \
		--configuration Debug \
		--derived-data-path $(BUILD_DIR) \
		$(SWIFT_MK_XCODEBUILD_ARGS)

swiftlint-analyze: generate-project
	@rm -rf "$(SWIFTLINT_ANALYZE_DERIVED_DATA)"
	@mkdir -p "$(ANALYZE_BUILD_DIR)"
	"$(SWIFT_MK_BIN)" toolchain build \
		--clean \
		--log-path "$(SWIFTLINT_ANALYZE_LOG)" \
		--generator $(FANCURVE_GENERATOR) \
		--workspace FanCurveApp.xcworkspace \
		--scheme FanCurve \
		--configuration Debug \
		--derived-data-path "$(SWIFTLINT_ANALYZE_DERIVED_DATA)" \
		$(SWIFT_MK_XCODEBUILD_NO_CACHE_ARGS)
	swiftlint analyze --strict \
		--config "$(SWIFT_MK_SWIFTLINT_CONFIG)" \
		--compiler-log-path "$(SWIFTLINT_ANALYZE_LOG)"

periphery-scan: lint-deadcode

launch-agent-audit: app
	@Scripts/AuditLaunchAgent.swift "$(APP_DEST)" "$(AGENT_PLIST_NAME)" "$(AGENT_BUNDLE_PROGRAM)" "$(AGENT_LABEL)"

run-audit:
	@Scripts/AuditMakeRun.swift Makefile

settings-layout-audit:
	@Scripts/SettingsLayoutAudit.swift Sources/Views

verify: launch-agent-audit run-audit settings-layout-audit log-audit test

quality: lint analyze verify
