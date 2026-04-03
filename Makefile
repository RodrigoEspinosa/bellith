PROJECT = Bellith.xcodeproj
SCHEME = Bellith
CONFIG = Debug
BUILD_DIR = $(shell xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -showBuildSettings 2>/dev/null | grep " BUILT_PRODUCTS_DIR" | sed 's/.*= //')

generate:
	xcodegen generate

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) build

run: build
	open "$(BUILD_DIR)/$(SCHEME).app"

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
