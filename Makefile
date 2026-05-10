-include Config/local.xcconfig

TUIST := $(shell command -v tuist 2>/dev/null || printf '%s' "mise x tuist@4.192.3 -- tuist")

CONFIGURATION = Release
BUILD_DIR = build
PRODUCTS_DIR = Products
CODE_SIGN_IDENTITY ?= Developer ID Application
DEVELOPMENT_TEAM ?= H3BMXM4W7H
BUNDLE_ID_PREFIX ?= io.goodkind
SWIFT_FORMAT_FILES = Sources Tests Project.swift Tuist.swift Tuist/Package.swift $(wildcard Workspace.swift)
SWIFTLINT_CONFIG = .swiftlint.yml
PERIPHERY_CONFIG = .periphery.yml
ANALYZE_BUILD_DIR = $(BUILD_DIR)/Analyze
SWIFTLINT_ANALYZE_DERIVED_DATA = $(ANALYZE_BUILD_DIR)/SwiftLintDerivedData
SWIFTLINT_ANALYZE_LOG = $(ANALYZE_BUILD_DIR)/swiftlint-xcodebuild.log
APP_NAME = FanCurve
AGENT_EXECUTABLE_NAME = FanCurveAgent
APP_DISPLAY_NAME = Fan Curve
APP_BUNDLE_NAME = $(APP_DISPLAY_NAME)
AGENT_DISPLAY_NAME = Fan Curve Background Control
HELPER_DISPLAY_NAME = Fan Curve Hardware Helper
HELPER_REPO ?= $(CURDIR)/../macos-smc-fan
HELPER_APP_SOURCE ?= $(HELPER_REPO)/Products/SMCFanHelper.app
HELPER_BUNDLE_ID ?= $(BUNDLE_ID_PREFIX).smcfanhelper
APP_BUNDLE_ID ?= $(BUNDLE_ID_PREFIX).fancurve
AGENT_BUNDLE_ID ?= $(BUNDLE_ID_PREFIX).fancurveagent
SHARED_SUITE_ID ?= $(BUNDLE_ID_PREFIX).fancurve.shared
DMG_NAME = $(APP_NAME)-$(CONFIGURATION)
MARKETING_VERSION ?= 0.1.0
CURRENT_PROJECT_VERSION ?= 1
SPARKLE_FEED_URL ?= https://goodkind.io/fancurve/appcast.xml
SPARKLE_PUBLIC_ED_KEY ?=
RELEASE_TAG ?= $(CURRENT_PROJECT_VERSION)-$(shell git rev-parse --short HEAD)
DMG_VOLUME_NAME = $(APP_DISPLAY_NAME)
DMG_STAGING_DIR = $(BUILD_DIR)/dmg
XCODE_PRODUCTS_DIR = $(BUILD_DIR)/Build/Products/$(CONFIGURATION)
APP_SOURCE = $(XCODE_PRODUCTS_DIR)/$(APP_BUNDLE_NAME).app
APP_DEST = $(PRODUCTS_DIR)/$(APP_BUNDLE_NAME).app
LEGACY_APP_DEST = $(PRODUCTS_DIR)/$(APP_NAME).app
INSTALL_USER_APP_DEST ?= $(HOME)/Applications/$(APP_BUNDLE_NAME).app
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
XCODE_BUILD_SETTINGS = CODE_SIGN_IDENTITY="$(CODE_SIGN_IDENTITY)" DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)" BUNDLE_ID_PREFIX="$(BUNDLE_ID_PREFIX)" HELPER_BUNDLE_ID="$(HELPER_BUNDLE_ID)" APP_BUNDLE_ID="$(APP_BUNDLE_ID)" AGENT_BUNDLE_ID="$(AGENT_BUNDLE_ID)" SHARED_SUITE_ID="$(SHARED_SUITE_ID)" HELPER_DISPLAY_NAME="$(HELPER_DISPLAY_NAME)" APP_DISPLAY_NAME="$(APP_DISPLAY_NAME)" AGENT_DISPLAY_NAME="$(AGENT_DISPLAY_NAME)" AGENT_EXECUTABLE_NAME="$(AGENT_EXECUTABLE_NAME)" SPARKLE_FEED_URL="$(SPARKLE_FEED_URL)" SPARKLE_PUBLIC_ED_KEY="$(SPARKLE_PUBLIC_ED_KEY)"
HELPER_BUILD_SETTINGS = CODE_SIGN_IDENTITY="$(CODE_SIGN_IDENTITY)" DEVELOPMENT_TEAM="$(DEVELOPMENT_TEAM)" BUNDLE_ID_PREFIX="$(BUNDLE_ID_PREFIX)" HELPER_BUNDLE_ID="$(HELPER_BUNDLE_ID)" APP_BUNDLE_ID="$(APP_BUNDLE_ID)" OWNER_APP_BUNDLE_ID="$(APP_BUNDLE_ID)" HELPER_APP_DISPLAY_NAME="$(HELPER_DISPLAY_NAME)" HELPER_DAEMON_DISPLAY_NAME="$(HELPER_DISPLAY_NAME)"

.PHONY: all install-dependencies install-analysis-tools build app install-user install-app run-installed dmg release-assets prepare-sparkle-updates sparkle-appcast clean generate-project generate-config-artifacts open-project test format format-check lint swiftlint-lint analyze xcode-analyze swiftlint-analyze periphery-scan launch-agent-audit run-audit verify quality run log-audit icons helper-artifacts

install-dependencies:
	$(TUIST) install

install-analysis-tools:
	@if ! command -v swift-format >/dev/null 2>&1; then \
		echo "swift-format not found. Install the Swift toolchain or swift-format before running analysis."; \
		exit 127; \
	fi
	@if ! command -v swiftlint >/dev/null 2>&1; then \
		brew install swiftlint; \
	fi
	@if ! command -v periphery >/dev/null 2>&1; then \
		brew install periphery; \
	fi

generate-config-artifacts:
	@TARGET_NAME="$(APP_NAME)" $(GENERATE_CONFIG_ENV) ./Scripts/GenerateConfig.swift
	@TARGET_NAME="$(AGENT_EXECUTABLE_NAME)" $(GENERATE_CONFIG_ENV) ./Scripts/GenerateConfig.swift

generate-project: generate-config-artifacts
	$(TUIST) generate --no-open

open-project: generate-project
	open FanCurveApp.xcworkspace

all: app

helper-artifacts:
	@test -d "$(HELPER_REPO)" || { echo "Missing helper repo: $(HELPER_REPO)"; exit 1; }
	$(MAKE) -C "$(HELPER_REPO)" generate-project
	xcodebuild -project "$(HELPER_REPO)/SMCFanApp.xcodeproj" \
		-scheme SMCFanHelper \
		-configuration $(CONFIGURATION) \
		-derivedDataPath "$(HELPER_REPO)/build" \
		$(HELPER_BUILD_SETTINGS) \
		APP_BUNDLE_ID="$(APP_BUNDLE_ID)" \
		ONLY_ACTIVE_ARCH=YES \
		build
	@mkdir -p "$(dir $(HELPER_APP_SOURCE))"
	@rm -rf "$(HELPER_APP_SOURCE)"
	@cp -R "$(HELPER_REPO)/build/Build/Products/$(CONFIGURATION)/SMCFanHelper.app" "$(HELPER_APP_SOURCE)"
	@test -x "$(HELPER_APP_SOURCE)/Contents/MacOS/$(HELPER_BUNDLE_ID)" || { echo "Missing helper executable in $(HELPER_APP_SOURCE)"; exit 1; }

icons:
	./Scripts/GenerateIcons.swift

build: generate-config-artifacts helper-artifacts icons generate-project
	xcodebuild -workspace FanCurveApp.xcworkspace \
		-scheme FanCurve \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(BUILD_DIR) \
		$(XCODE_BUILD_SETTINGS) \
		MARKETING_VERSION="$(MARKETING_VERSION)" \
		CURRENT_PROJECT_VERSION="$(CURRENT_PROJECT_VERSION)" \
		SMC_FAN_HELPER_APP="$(HELPER_APP_SOURCE)"

app: build
	@mkdir -p $(PRODUCTS_DIR)
	@./Scripts/RefreshIconCache.swift "$(APP_SOURCE)" "$(ICON_HASH_STAMP)"
	@rm -rf "$(APP_DEST)" "$(LEGACY_APP_DEST)"
	@cp -R "$(APP_SOURCE)" "$(PRODUCTS_DIR)/"
	@./Scripts/RefreshIconCache.swift "$(APP_DEST)" "$(ICON_HASH_STAMP)"

install-user: app
	@mkdir -p "$(HOME)/Applications"
	@rm -rf "$(INSTALL_USER_APP_DEST)"
	@cp -R "$(APP_DEST)" "$(INSTALL_USER_APP_DEST)"

install-app: app
	@rm -rf "$(INSTALL_APP_DEST)"
	@cp -R "$(APP_DEST)" "$(INSTALL_APP_DEST)"

run-installed: install-user
	@open -na "$(INSTALL_USER_APP_DEST)"

dmg: app
	@mkdir -p "$(PRODUCTS_DIR)" "$(DMG_STAGING_DIR)"
	@rm -rf "$(DMG_STAGING_DIR)/$(APP_BUNDLE_NAME).app" "$(DMG_STAGING_DIR)/Applications" "$(DMG_PATH)"
	@cp -R "$(APP_DEST)" "$(DMG_STAGING_DIR)/"
	@ln -s /Applications "$(DMG_STAGING_DIR)/Applications"
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

run: app
	@pkill -x "$(APP_NAME)" 2>/dev/null || true
	@open "$(APP_DEST)"

test: generate-config-artifacts helper-artifacts generate-project
	xcodebuild -workspace FanCurveApp.xcworkspace \
		-scheme FanCurve \
		-configuration Debug \
		-derivedDataPath $(BUILD_DIR) \
		$(XCODE_BUILD_SETTINGS) \
		SMC_FAN_HELPER_APP="$(HELPER_APP_SOURCE)" \
		test

format:
	swift-format format --in-place --recursive $(SWIFT_FORMAT_FILES)

format-check:
	swift-format lint --strict --recursive $(SWIFT_FORMAT_FILES)

swiftlint-lint:
	swiftlint lint --strict --config "$(SWIFTLINT_CONFIG)"

lint: format-check swiftlint-lint log-audit

xcode-analyze: generate-project
	xcodebuild -workspace FanCurveApp.xcworkspace \
		-scheme FanCurve \
		-configuration Debug \
		-derivedDataPath $(BUILD_DIR) \
		analyze

swiftlint-analyze: generate-project
	@rm -rf "$(SWIFTLINT_ANALYZE_DERIVED_DATA)"
	@mkdir -p "$(ANALYZE_BUILD_DIR)"
	xcodebuild -workspace FanCurveApp.xcworkspace \
		-scheme FanCurve \
		-configuration Debug \
		-derivedDataPath "$(SWIFTLINT_ANALYZE_DERIVED_DATA)" \
		clean build > "$(SWIFTLINT_ANALYZE_LOG)"
	swiftlint analyze --strict \
		--config "$(SWIFTLINT_CONFIG)" \
		--compiler-log-path "$(SWIFTLINT_ANALYZE_LOG)"

periphery-scan: generate-project
	@if ! command -v periphery >/dev/null 2>&1; then \
		echo "periphery not found. Install it with: brew install periphery"; \
		exit 127; \
	fi
	periphery scan --config "$(PERIPHERY_CONFIG)"

analyze: xcode-analyze swiftlint-analyze periphery-scan

launch-agent-audit: app
	@Scripts/AuditLaunchAgent.swift "$(APP_DEST)" "$(AGENT_PLIST_NAME)" "$(AGENT_BUNDLE_PROGRAM)" "$(AGENT_LABEL)"

run-audit:
	@Scripts/AuditMakeRun.swift Makefile

verify: launch-agent-audit run-audit log-audit test

quality: lint analyze verify

clean:
	rm -rf $(BUILD_DIR) $(PRODUCTS_DIR) FanCurveApp.xcworkspace FanCurveApp.xcodeproj

log-audit:
	@Scripts/AuditLogging.swift Sources
