XCODEBUILD := /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
SCHEME     := MacRaclette
PROJECT    := MacRaclette.xcodeproj
BUILD_DIR  := .build
APP_NAME   := MacRaclette

VERSION    := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
NEXT_PATCH := $(shell echo $(VERSION) | awk -F. '{printf "%s.%s.%d", $$1, $$2, $$3+1}')

APP        := $(BUILD_DIR)/Build/Products/Release/$(APP_NAME).app
STAGING    := $(BUILD_DIR)/dmg-staging
DMG        := dist/$(APP_NAME)-$(VERSION).dmg

ICON_SRC := MacRaclette/Assets.xcassets/AppIcon.appiconset/icon_1024.png
ICON_DIR := MacRaclette/Assets.xcassets/AppIcon.appiconset

.PHONY: build dmg release tag clean icons

## Build the Release .app
build:
	$(XCODEBUILD) \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(BUILD_DIR) \
		build 2>&1 | tee /tmp/xcodebuild.log | grep -E "(error:|BUILD SUCCEEDED|BUILD FAILED)"; \
	grep -q "BUILD SUCCEEDED" /tmp/xcodebuild.log

## Create a DMG from the last build
dmg: build
	@mkdir -p dist
	@rm -f "$(DMG)"
	create-dmg \
		--volname "$(APP_NAME)" \
		--window-pos 200 120 \
		--window-size 540 380 \
		--icon-size 128 \
		--icon "$(APP_NAME).app" 130 180 \
		--hide-extension "$(APP_NAME).app" \
		--app-drop-link 410 180 \
		--no-internet-enable \
		"$(DMG)" \
		"$(APP)"
	@echo "→ $(DMG)"

## Tag a new patch version (e.g. v1.0.0 → v1.0.1)
tag:
	@echo "Tagging $(NEXT_PATCH)"
	git tag $(NEXT_PATCH)
	git push origin $(NEXT_PATCH)

## Build DMG and open GitHub to publish the release manually
release: dmg
	@echo "→ DMG prêt : $(DMG)"
	@echo "→ Ouvre GitHub pour créer la release manuellement :"
	open "https://github.com/MagnusDot/MacRaclette/releases/new?tag=$(VERSION)"
	open "$(shell pwd)/dist"

## Generate all AppIcon sizes from icon_1024.png
icons:
	@test -f "$(ICON_SRC)" || (echo "❌  Mets ton PNG 1024×1024 dans $(ICON_SRC)" && exit 1)
	@for size in 16 32 128 256 512; do \
		sips -z $$size $$size "$(ICON_SRC)" --out "$(ICON_DIR)/icon_$${size}x$${size}.png"    > /dev/null; \
		sips -z $$((size*2)) $$((size*2)) "$(ICON_SRC)" --out "$(ICON_DIR)/icon_$${size}x$${size}@2x.png" > /dev/null; \
	done
	@echo "→ Icônes générées dans $(ICON_DIR)"
	@$(MAKE) _update_contents_json

_update_contents_json:
	@python3 -c "\
import json, sys; \
sizes = [16,32,128,256,512]; \
images = []; \
[images.extend([{'idiom':'mac','scale':'1x','size':f'{s}x{s}','filename':f'icon_{s}x{s}.png'}, \
                {'idiom':'mac','scale':'2x','size':f'{s}x{s}','filename':f'icon_{s}x{s}@2x.png'}]) for s in sizes]; \
data = {'images': images, 'info': {'author': 'xcode', 'version': 1}}; \
json.dump(data, open('$(ICON_DIR)/Contents.json', 'w'), indent=2) \
"
	@echo "→ Contents.json mis à jour"

## Remove build artifacts
clean:
	rm -rf $(BUILD_DIR)
