-include Config/local.xcconfig

CONFIGURATION = Release
BUILD_DIR = build
PRODUCTS_DIR = Products

.PHONY: all clean generate-project test format run

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
