XCODEBUILD := /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
SCHEME     := MacRaclette
PROJECT    := MacRaclette.xcodeproj
BUILD_DIR  := .build
APP_NAME   := MacRaclette

VERSION    := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
NEXT_PATCH := $(shell echo $(VERSION) | awk -F. '{printf "%s.%s.%d", $$1, $$2, $$3+1}')

APP        := $(BUILD_DIR)/Release/$(APP_NAME).app
STAGING    := $(BUILD_DIR)/dmg-staging
DMG        := $(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg

.PHONY: build dmg release tag clean

## Build the Release .app
build:
	$(XCODEBUILD) \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(BUILD_DIR) \
		build | xcbeautify 2>/dev/null || cat

## Create a DMG from the last build
dmg: build
	@rm -rf "$(STAGING)"
	@mkdir -p "$(STAGING)"
	@cp -r "$(APP)" "$(STAGING)/"
	@ln -sf /Applications "$(STAGING)/Applications"
	@rm -f "$(DMG)"
	hdiutil create \
		-volname "$(APP_NAME)" \
		-srcfolder "$(STAGING)" \
		-ov -format UDZO \
		-o "$(DMG)"
	@echo "→ $(DMG)"

## Tag a new patch version (e.g. v1.0.0 → v1.0.1)
tag:
	@echo "Tagging $(NEXT_PATCH)"
	git tag $(NEXT_PATCH)
	git push origin $(NEXT_PATCH)

## Build DMG and publish a GitHub Release for VERSION
release: dmg
	gh release create $(VERSION) "$(DMG)" \
		--title "$(APP_NAME) $(VERSION)" \
		--notes "## Installation\n1. Ouvre le DMG\n2. Glisse $(APP_NAME) dans Applications\n3. Premier lancement : clic-droit → Ouvrir"
	@echo "→ Released $(VERSION)"

## Remove build artifacts
clean:
	rm -rf $(BUILD_DIR)
