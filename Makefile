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
TEST_CONTROL_EXECUTABLE_NAME = FanCurveTestControl
UI_TEST_SESSION_PATH ?=
UI_TEST_RESULT_BUNDLE_PATH ?=
UI_TEST_DERIVED_DATA_PATH = $(CURDIR)/$(BUILD_DIR)/UITests
UI_TEST_CANONICAL_APP_PATH = /Applications/Fan Curve.app
APP_DISPLAY_NAME = Fan Curve
APP_BUNDLE_NAME = $(APP_DISPLAY_NAME)
AGENT_DISPLAY_NAME = Fan Curve Background Control
HELPER_DISPLAY_NAME = Fan Curve Hardware Helper
HELPER_BUNDLE_ID ?= $(BUNDLE_ID_PREFIX).smcfanhelper
export TUIST_HELPER_EXECUTABLE_NAME := $(HELPER_BUNDLE_ID)
APP_BUNDLE_ID ?= $(BUNDLE_ID_PREFIX).fancurve
AGENT_BUNDLE_ID ?= $(BUNDLE_ID_PREFIX).fancurveagent
SHARED_SUITE_ID ?= $(BUNDLE_ID_PREFIX).fancurve.shared
DMG_NAME = $(APP_NAME)-$(CONFIGURATION)
RELEASE_TRACK ?= stable
ARTIFACT_VERSION ?= Release
MARKETING_VERSION ?= 0.0.0
CURRENT_PROJECT_VERSION ?= 0
SPARKLE_APPCAST_FEED_PATH = $(if $(filter prerelease,$(RELEASE_TRACK)),prerelease/appcast.xml,appcast.xml)
SPARKLE_FEED_URL = https://goodkind.io/fancurve/$(SPARKLE_APPCAST_FEED_PATH)
# Sparkle's Ed25519 PUBLIC key, read from a committed file so the make value
# stays byte-exact: a whitespace-dirtied SUPublicEDKey reaches Info.plist and
# generate_appcast then sees a key mismatch and silently emits an unsigned
# appcast, which bricks every shipped updater.
SPARKLE_PUBLIC_ED_KEY ?= $(shell cat Config/sparkle.pub 2>/dev/null)
RELEASE_TAG ?= $(CURRENT_PROJECT_VERSION)-$(shell git rev-parse --short HEAD)
GH_REPOSITORY ?= agoodkind/macos-fan-curve
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
RELEASE_DMG_NAME = $(APP_NAME)-$(ARTIFACT_VERSION).dmg
RELEASE_DMG_PATH = $(PRODUCTS_DIR)/$(RELEASE_DMG_NAME)
SPARKLE_UPDATES_DIR = $(BUILD_DIR)/sparkle-updates
SPARKLE_GENERATED_APPCAST = $(SPARKLE_UPDATES_DIR)/appcast.xml
SPARKLE_ASSET_TAGS = $(SPARKLE_UPDATES_DIR)/asset-tags.tsv
GENERATE_CONFIG_ENV = SRCROOT="$(CURDIR)" CONFIGURATION="$(CONFIGURATION)" FANCURVE_TEST_CONTROL_PATH="$(FANCURVE_TEST_CONTROL_PATH)" HELPER_BUNDLE_ID="$(HELPER_BUNDLE_ID)" HELPER_DISPLAY_NAME="$(HELPER_DISPLAY_NAME)" APP_BUNDLE_ID="$(APP_BUNDLE_ID)" APP_DISPLAY_NAME="$(APP_DISPLAY_NAME)" AGENT_BUNDLE_ID="$(AGENT_BUNDLE_ID)" AGENT_DISPLAY_NAME="$(AGENT_DISPLAY_NAME)" AGENT_EXECUTABLE_NAME="$(AGENT_EXECUTABLE_NAME)" SHARED_SUITE_ID="$(SHARED_SUITE_ID)" DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)" BUNDLE_ID_PREFIX="$(BUNDLE_ID_PREFIX)" MARKETING_VERSION="$(MARKETING_VERSION)" CURRENT_PROJECT_VERSION="$(CURRENT_PROJECT_VERSION)" SPARKLE_FEED_URL="$(SPARKLE_FEED_URL)" SPARKLE_PUBLIC_ED_KEY="$(SPARKLE_PUBLIC_ED_KEY)"
# Signing is owned by swift-mk (XCODE_XCCONFIG_FILE override), not set here.
XCODE_BUILD_SETTINGS = FANCURVE_TEST_CONTROL_PATH="$(FANCURVE_TEST_CONTROL_PATH)" BUNDLE_ID_PREFIX="$(BUNDLE_ID_PREFIX)" HELPER_BUNDLE_ID="$(HELPER_BUNDLE_ID)" APP_BUNDLE_ID="$(APP_BUNDLE_ID)" AGENT_BUNDLE_ID="$(AGENT_BUNDLE_ID)" SHARED_SUITE_ID="$(SHARED_SUITE_ID)" HELPER_DISPLAY_NAME="$(HELPER_DISPLAY_NAME)" APP_DISPLAY_NAME="$(APP_DISPLAY_NAME)" AGENT_DISPLAY_NAME="$(AGENT_DISPLAY_NAME)" AGENT_EXECUTABLE_NAME="$(AGENT_EXECUTABLE_NAME)" MARKETING_VERSION="$(MARKETING_VERSION)" CURRENT_PROJECT_VERSION="$(CURRENT_PROJECT_VERSION)" SPARKLE_FEED_URL="$(SPARKLE_FEED_URL)" SPARKLE_PUBLIC_ED_KEY="$(SPARKLE_PUBLIC_ED_KEY)"

SWIFT_MK_MODULES := swift-build.mk swift-release.mk
# This project defines its own `run` (Debug build deployed to /Applications). The
# swift-build.mk module skips its generic `run` when this is set, avoiding a Make
# "overriding commands" warning. Takes effect once the guard is synced into .make/.
SWIFT_MK_OWN_RUN := 1
SWIFT_BUILD_CMD := $(MAKE) app-local
# Release artifacts for the shared _release.yml pipeline: the signed DMG into
# dist/. MARKETING_VERSION/CURRENT_PROJECT_VERSION/RELEASE_TAG arrive as env
# from the workflow's release-meta job.
SWIFT_MK_RELEASE_BUILD_CMD := $(MAKE) release-assets && cp "$(RELEASE_DMG_PATH)" dist/
# The project-build recipe writes its index store under BUILD_DIR, so the
# dead-code gate reads from there. A clean build before the scan keeps the index
# free of stale units from earlier incremental builds.
SWIFT_MK_DERIVED_DATA := $(BUILD_DIR)
SWIFT_TEST_CMD := $(MAKE) test-local
SWIFT_GENERATE_CMD := $(MAKE) generate-project
SWIFT_CLEAN_CMD := rm -rf $(BUILD_DIR) $(PRODUCTS_DIR) FanCurveApp.xcworkspace FanCurveApp.xcodeproj
SWIFT_ANALYZE_CMD := $(MAKE) xcode-analyze swiftlint-analyze
SWIFT_FORMAT_TARGETS := $(SWIFT_FORMAT_FILES)
SWIFTLINT_TARGETS := $(SWIFT_FORMAT_FILES)
SWIFTCHECK_EXTRA_TARGETS := $(SWIFT_FORMAT_FILES)
SWIFT_AUDIT_EXTRA_CMD := Scripts/Tests/release-track-contract.sh && Scripts/Tests/select-appcast-releases.sh && Scripts/Tests/prepare-appcast-history.sh && Scripts/Tests/rewrite-appcast-urls.sh && Scripts/Tests/generate-sparkle-appcast.sh

# Generator names are data, bound to variables so no recipe line names a build
# tool directly; every build/test/analyze routes through the swift-mk toolchain.
FANCURVE_GENERATOR := tuist
SWIFT_XCODE_GENERATOR := $(FANCURVE_GENERATOR)
SWIFT_XCODE_WORKSPACE := FanCurveApp.xcworkspace
SWIFT_XCODE_SCHEME := FanCurveCoverage
# The engine coverage build runs at Debug; the engine derives and owns the rest.
SWIFT_XCODE_COVERAGE_CONFIGURATION := Debug
# The tuist Generate Config build phase needs these project build settings in the
# xcodebuild environment; the engine shell-parses them so quoted values with spaces
# survive.
SWIFT_XCODE_BUILD_SETTINGS := $(XCODE_BUILD_SETTINGS)

include bootstrap.mk

.PHONY: all install-dependencies install-analysis-tools app app-local run project-build install-app dmg release-assets prepare-sparkle-updates generate-sparkle-appcast sparkle-appcast appcast generate-project generate-config-artifacts open-project test-agent test-control-build test-control-build-local test-control-contract test-control-signing test-local test-ui test-ui-build test-ui-build-local format format-check swiftlint-lint xcode-analyze swiftlint-analyze periphery-scan launch-agent-audit run-audit settings-layout-audit verify quality icons

all: app

install-dependencies: swift-mk-bin
	"$(SWIFT_MK_BIN)" toolchain install --generator $(FANCURVE_GENERATOR)

install-analysis-tools: lint-tools

generate-config-artifacts:
	@TARGET_NAME="$(APP_NAME)" $(GENERATE_CONFIG_ENV) ./Scripts/GenerateConfig.swift
	@TARGET_NAME="$(AGENT_EXECUTABLE_NAME)" $(GENERATE_CONFIG_ENV) ./Scripts/GenerateConfig.swift
	@TARGET_NAME="SMCFanHelper" $(GENERATE_CONFIG_ENV) ./Scripts/GenerateConfig.swift

generate-project: swift-mk-bin generate-config-artifacts
	"$(SWIFT_MK_BIN)" toolchain install --generator $(FANCURVE_GENERATOR)
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
		$(SWIFT_MK_XCODEBUILD_ARGS)

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
# runs that copy for debugging; the canonical install lives at /Applications.
run:
	$(MAKE) CONFIGURATION=Debug build
	@rm -rf "$(INSTALL_APP_DEST)"
	@cp -R "$(APP_DEST)" "$(INSTALL_APP_DEST)"
	@Scripts/TerminateAgentInstances.swift "$(AGENT_LABEL)"
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
		SWIFT_MK_SIGN_IDENTITY="$(DMG_SIGN_IDENTITY)" "$(SWIFT_MK_BIN)" codesign-run --mode dmg "$(DMG_PATH)"; \
	fi

release-assets: dmg
	@cp "$(DMG_PATH)" "$(RELEASE_DMG_PATH)"

prepare-sparkle-updates:
	@test -f "$(RELEASE_DMG_PATH)"
	@rm -rf "$(SPARKLE_UPDATES_DIR)"
	@mkdir -p "$(SPARKLE_UPDATES_DIR)"
	@cp "$(RELEASE_DMG_PATH)" "$(SPARKLE_UPDATES_DIR)/"
	@printf '%s\t%s\n' "$(RELEASE_TAG)" "$(RELEASE_DMG_NAME)" > "$(SPARKLE_ASSET_TAGS)"
	@$(MAKE) generate-sparkle-appcast

generate-sparkle-appcast:
	@test -s "$(SPARKLE_ASSET_TAGS)"
	@test "$$(find "$(SPARKLE_UPDATES_DIR)" -maxdepth 1 -name '$(APP_NAME)-*.dmg' -print | wc -l | tr -d ' ')" -gt 0
	@if [ -z "$${SPARKLE_PRIVATE_KEY_FILE:-}" ] || [ ! -s "$${SPARKLE_PRIVATE_KEY_FILE:-}" ]; then \
		echo "generate-sparkle-appcast: SPARKLE_PRIVATE_KEY_FILE must point at the Ed25519 private key."; \
		echo "  Shipped apps embed SUPublicEDKey, so an unsigned appcast bricks every update."; \
		exit 1; \
	fi
	@SPARKLE_APPCAST_TOOL="$$(Scripts/FindSparkleTool.swift "$(BUILD_DIR)" generate_appcast)"; \
	"$${SPARKLE_APPCAST_TOOL}" \
		--ed-key-file "$${SPARKLE_PRIVATE_KEY_FILE}" \
		--download-url-prefix "https://github.com/$(GH_REPOSITORY)/releases/download/__RELEASE_TAG__/" \
		--maximum-versions 0 \
		--maximum-deltas 0 \
		"$(SPARKLE_UPDATES_DIR)"
	@Scripts/RewriteAppcastURLs.swift \
		--appcast "$(SPARKLE_GENERATED_APPCAST)" \
		--mapping "$(SPARKLE_ASSET_TAGS)" \
		--repository "$(GH_REPOSITORY)"
	@unsigned="$$(awk '/<enclosure /{ if ($$0 !~ /sparkle:edSignature="/) print }' "$(SPARKLE_GENERATED_APPCAST)")"; \
	if [ -n "$$unsigned" ]; then \
		echo "generate-sparkle-appcast: generate_appcast produced unsigned enclosures:"; \
		echo "$$unsigned"; \
		echo "  This means the private key does not pair with SUPublicEDKey ($(SPARKLE_PUBLIC_ED_KEY))."; \
		exit 1; \
	fi
	@echo "generate-sparkle-appcast: every enclosure carries an EdDSA signature."

sparkle-appcast: release-assets prepare-sparkle-updates

# Regenerate the appcast for an already-published release: download its DMG,
# derive the artifact version from the asset name, and run the Sparkle generator.
# RELEASE_TAG names the release; SPARKLE_PRIVATE_KEY_FILE (optional) signs.
appcast:
	@if [ -z "$(strip $(RELEASE_TAG))" ]; then echo "appcast: RELEASE_TAG is required"; exit 1; fi
	@mkdir -p $(PRODUCTS_DIR)
	gh release download "$(RELEASE_TAG)" --pattern "$(APP_NAME)-*.dmg" --dir $(PRODUCTS_DIR) --clobber
	@dmg="$$(ls $(PRODUCTS_DIR)/$(APP_NAME)-*.dmg | sed -n 1p)"; \
	artifact_version="$$(basename "$$dmg" .dmg | sed 's/^$(APP_NAME)-//')"; \
	$(MAKE) prepare-sparkle-updates \
		ARTIFACT_VERSION="$$artifact_version" \
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

test-agent: generate-config-artifacts generate-project
	"$(SWIFT_MK_BIN)" toolchain test \
		--generator $(FANCURVE_GENERATOR) \
		--workspace FanCurveApp.xcworkspace \
		--scheme FanCurveAgentTests \
		--configuration Debug \
		--derived-data-path $(BUILD_DIR) \
		$(XCODE_BUILD_SETTINGS) \
		$(SWIFT_MK_XCODEBUILD_ARGS)

test-control-contract: generate-config-artifacts generate-project
	"$(SWIFT_MK_BIN)" toolchain test \
		--generator $(FANCURVE_GENERATOR) \
		--workspace FanCurveApp.xcworkspace \
		--scheme TestControlContractTests \
		--configuration Debug \
		--derived-data-path $(BUILD_DIR) \
		$(XCODE_BUILD_SETTINGS) \
		$(SWIFT_MK_XCODEBUILD_ARGS)

test-ui: FANCURVE_TEST_CONTROL_PATH := $(UI_TEST_SESSION_PATH)
test-ui: generate-config-artifacts generate-project
	@SWIFT_MK_BIN="$(SWIFT_MK_BIN)" \
		FANCURVE_GENERATOR="$(FANCURVE_GENERATOR)" \
		UI_TEST_WORKSPACE="$(CURDIR)/FanCurveApp.xcworkspace" \
		UI_TEST_DERIVED_DATA_PATH="$(UI_TEST_DERIVED_DATA_PATH)" \
		UI_TEST_SESSION_PATH="$(UI_TEST_SESSION_PATH)" \
		UI_TEST_RESULT_BUNDLE_PATH="$(UI_TEST_RESULT_BUNDLE_PATH)" \
		UI_TEST_CANONICAL_APP_PATH="$(UI_TEST_CANONICAL_APP_PATH)" \
		CODE_SIGN_IDENTITY="$(CODE_SIGN_IDENTITY)" \
		DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)" \
		BUNDLE_ID_PREFIX="$(BUNDLE_ID_PREFIX)" \
		HELPER_BUNDLE_ID="$(HELPER_BUNDLE_ID)" \
		APP_BUNDLE_ID="$(APP_BUNDLE_ID)" \
		AGENT_BUNDLE_ID="$(AGENT_BUNDLE_ID)" \
		SHARED_SUITE_ID="$(SHARED_SUITE_ID)" \
		HELPER_DISPLAY_NAME="$(HELPER_DISPLAY_NAME)" \
		APP_DISPLAY_NAME="$(APP_DISPLAY_NAME)" \
		AGENT_DISPLAY_NAME="$(AGENT_DISPLAY_NAME)" \
		AGENT_EXECUTABLE_NAME="$(AGENT_EXECUTABLE_NAME)" \
		SPARKLE_FEED_URL="$(SPARKLE_FEED_URL)" \
		SPARKLE_PUBLIC_ED_KEY="$(SPARKLE_PUBLIC_ED_KEY)" \
		Scripts/RunFanCurveUITests.sh

test-ui-build:
	$(MAKE) CONFIGURATION=Debug \
		SWIFT_BUILD_CMD='$(MAKE) test-ui-build-local' \
		build

test-ui-build-local: generate-config-artifacts generate-project
	"$(SWIFT_MK_BIN)" toolchain build \
		--generator $(FANCURVE_GENERATOR) \
		--workspace FanCurveApp.xcworkspace \
		--scheme FanCurveUITests \
		--configuration Debug \
		--derived-data-path $(UI_TEST_DERIVED_DATA_PATH) \
		$(XCODE_BUILD_SETTINGS) \
		$(SWIFT_MK_XCODEBUILD_ARGS)

test-control-build:
	$(MAKE) CONFIGURATION=Debug \
		SWIFT_BUILD_CMD='$(MAKE) test-control-build-local' \
		build

test-control-build-local: generate-config-artifacts generate-project
	"$(SWIFT_MK_BIN)" toolchain build \
		--generator $(FANCURVE_GENERATOR) \
		--workspace FanCurveApp.xcworkspace \
		--scheme $(TEST_CONTROL_EXECUTABLE_NAME) \
		--configuration Debug \
		--derived-data-path $(BUILD_DIR) \
		$(XCODE_BUILD_SETTINGS) \
		$(SWIFT_MK_XCODEBUILD_ARGS)
	$(MAKE) test-control-signing

test-control-signing: swift-mk-bin
	@CODE_SIGN_IDENTITY="$(CODE_SIGN_IDENTITY)" \
		DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)" \
		XCODE_XCCONFIG_FILE="$(CURDIR)/.make/signing.xcconfig" \
		"$(SWIFT_MK_BIN)" verify-signing settings \
		--workspace FanCurveApp.xcworkspace \
		--scheme $(TEST_CONTROL_EXECUTABLE_NAME) \
		--configuration Debug
	@CODE_SIGN_IDENTITY="$(CODE_SIGN_IDENTITY)" \
		DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)" \
		"$(SWIFT_MK_BIN)" verify-signing artifacts \
		"$(BUILD_DIR)/Build/Products/Debug/$(TEST_CONTROL_EXECUTABLE_NAME)"

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
	@Scripts/AuditMakeRunTests.swift Scripts/AuditMakeRun.swift
	@Scripts/AuditMakeRun.swift Makefile

settings-layout-audit:
	@Scripts/SettingsLayoutAudit.swift Sources/Views

verify: launch-agent-audit run-audit settings-layout-audit log-audit test

quality: lint analyze verify
