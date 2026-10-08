PROJECT = Bellith.xcodeproj
SCHEME = Bellith
CONFIG = Debug
# Keep command-line builds separate from Xcode's default DerivedData database.
DERIVED_DATA ?= $(CURDIR)/DerivedData/command-line
BUILD_DIR = $(DERIVED_DATA)/Build/Products/$(CONFIG)

generate:
	xcodegen generate

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -derivedDataPath "$(DERIVED_DATA)" build

run: build
	open "$(BUILD_DIR)/$(SCHEME).app"

test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath "$(DERIVED_DATA)" test

test-creative:
	bash scripts/test-creative.sh

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

.PHONY: generate build run test test-creative lint lint-fix clean loc
