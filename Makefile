-include Config/local.xcconfig

CONFIGURATION = Release
BUILD_DIR = build
PRODUCTS_DIR = Products

.PHONY: all clean generate-project test format run log-audit

generate-project:
	xcodegen generate

all: generate-project
	xcodebuild -project FanCurveApp.xcodeproj \
		-scheme FanCurve \
		-configuration $(CONFIGURATION) \
		-derivedDataPath $(BUILD_DIR) \
		ONLY_ACTIVE_ARCH=YES \
		build
	@mkdir -p $(PRODUCTS_DIR)
	@cp -R "$(BUILD_DIR)/Build/Products/$(CONFIGURATION)/FanCurve.app" "$(PRODUCTS_DIR)/"

run: all
	open "$(PRODUCTS_DIR)/FanCurve.app"

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
