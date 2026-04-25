-include Config/local.xcconfig

CONFIGURATION = Release
BUILD_DIR = build
PRODUCTS_DIR = Products
APP_NAME = FanCurve
DMG_NAME = $(APP_NAME)-$(CONFIGURATION)
DMG_VOLUME_NAME = $(APP_NAME)
DMG_STAGING_DIR = $(BUILD_DIR)/dmg
XCODE_PRODUCTS_DIR = $(BUILD_DIR)/Build/Products/$(CONFIGURATION)
APP_SOURCE = $(XCODE_PRODUCTS_DIR)/$(APP_NAME).app
APP_DEST = $(PRODUCTS_DIR)/$(APP_NAME).app
DMG_PATH = $(PRODUCTS_DIR)/$(DMG_NAME).dmg

.PHONY: all build app dmg clean generate-project test format run log-audit

generate-project:
	xcodegen generate

all: app

build: generate-project
	xcodebuild -project FanCurveApp.xcodeproj \
		-scheme FanCurve \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(BUILD_DIR) \
		ONLY_ACTIVE_ARCH=YES \
		build

app: build
	@mkdir -p $(PRODUCTS_DIR)
	@rm -rf "$(APP_DEST)"
	@cp -R "$(APP_SOURCE)" "$(PRODUCTS_DIR)/"

dmg: app
	@mkdir -p "$(PRODUCTS_DIR)" "$(DMG_STAGING_DIR)"
	@rm -rf "$(DMG_STAGING_DIR)/$(APP_NAME).app" "$(DMG_STAGING_DIR)/Applications" "$(DMG_PATH)"
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

run: app
	open "$(APP_DEST)"

test:
	swift test

format:
	swift-format format --in-place --recursive Sources/

clean:
	rm -rf $(BUILD_DIR) $(PRODUCTS_DIR) FanCurveApp.xcodeproj

# Guard A from the AppLog rules. Fails if any Swift source uses
# print(), NSLog, swift-log Logger(), or os_log directly. The bridge
# package itself is exempt; CLI stdout helpers are not used here.
log-audit:
	@! grep -rEn '(^|[^a-zA-Z_])(print|NSLog|os_log)\(|Logger\(label:|Logger\(subsystem:' Sources \
		--include='*.swift' \
		| grep -v 'CLIOut\.print\|CLIOut\.err' \
		| grep -v ':[[:space:]]*//' \
		|| (echo "log-audit failed: see matches above" && exit 1)
	@echo "log-audit: ok"
