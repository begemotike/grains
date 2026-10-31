PROJECT  := Grains.xcodeproj
SCHEME   := Grains
DERIVED  := build
APP      := $(DERIVED)/Build/Products/Debug/Grains.app
XCB      := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
			-derivedDataPath $(DERIVED) -destination 'platform=macOS,arch=arm64'

.PHONY: all gen build test core-test app-test run path clean icon

all: test build path

gen:
	xcodegen generate --quiet

# Headless package tests (core, reports, MCP). Fast; no Xcode project needed.
core-test:
	swift test

app-test: gen
	$(XCB) test -quiet

test: core-test app-test

build: gen
	$(XCB) build -quiet

path:
	@echo "Built app: $(abspath $(APP))"

run: build
	open "$(APP)"

icon:
	swift scripts/make-icon.swift build/AppIcon.png && scripts/make-icns.sh build/AppIcon.png App/Resources/AppIcon.icns

clean:
	rm -rf $(DERIVED) .build $(PROJECT)
