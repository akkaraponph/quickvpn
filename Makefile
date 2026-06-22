FLUTTER ?= flutter
APP_NAME := quickvpn
MACOS_APP := build/macos/Build/Products/Release/$(APP_NAME).app
DMG := build/$(APP_NAME).dmg

.PHONY: build-macos run-macos open-macos dmg clean help

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
	./scripts/make_dmg.sh "$(MACOS_APP)" "$(DMG)" "Quick"

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
