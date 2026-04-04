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

test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug test

lint:
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --config .swiftlint.yml; \
	else \
		echo "SwiftLint not installed. Install with: brew install swiftlint"; \
	fi

lint-fix:
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --fix --config .swiftlint.yml; \
	else \
		echo "SwiftLint not installed. Install with: brew install swiftlint"; \
	fi

clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
	rm -rf DerivedData

loc:
	@find Bellith -name "*.swift" -exec cat {} + | wc -l

.PHONY: generate build run test lint lint-fix clean loc
