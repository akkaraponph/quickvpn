FLUTTER ?= flutter
# macOS product/app name — must match PRODUCT_NAME in macos/Runner/Configs/AppInfo.xcconfig.
# Drives the built .app filename, the menu-bar name, and the mounted volume name.
PRODUCT_NAME := QuickVPN
# Lowercase slug used only for the .dmg filename, e.g. quickvpn-v1.0.0.dmg
APP_SLUG := quickvpn
# Version name (without build number) read from pubspec.yaml, e.g. 1.0.0
VERSION := $(shell awk '/^version:/ {split($$2, a, "+"); print a[1]; exit}' pubspec.yaml)
MACOS_APP := build/macos/Build/Products/Release/$(PRODUCT_NAME).app
DMG := build/$(APP_SLUG)-v$(VERSION).dmg

.PHONY: build-macos run-macos open-macos dmg linux win clean help

## Build the macOS app (release)
build-macos:
	$(FLUTTER) build macos --release
	@echo "Built: $(MACOS_APP)"

## Run the app on macOS
run-macos:
	$(FLUTTER) run -d macos

## Reveal the built .app in Finder
open-macos:
	open -R "$(MACOS_APP)"

## Build a branded, drag-to-Applications .dmg installer
dmg: build-macos
	./scripts/make_dmg.sh "$(MACOS_APP)" "$(DMG)" "$(PRODUCT_NAME)"

## Build + package the Linux release tarball (run on Linux)
linux:
	./scripts/make_linux.sh

## Build + package the Windows installer/zip (run on Windows)
win:
	powershell -ExecutionPolicy Bypass -File scripts/make_win.ps1

## Remove build artifacts
clean:
	$(FLUTTER) clean

## Show available targets
help:
	@grep -B1 -E '^[a-zA-Z0-9_-]+:' $(MAKEFILE_LIST) \
		| grep -A1 '^##' \
		| sed -E 's/^## ?//; s/:.*//; /^--$$/d' \
		| paste - - \
		| awk -F'\t' '{printf "  \033[36m%-14s\033[0m %s\n", $$2, $$1}'

.DEFAULT_GOAL := help
