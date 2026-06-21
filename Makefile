FLUTTER ?= flutter
MACOS_APP := build/macos/Build/Products/Release/quickvpn.app

.PHONY: build-macos run-macos open-macos clean help

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
