.PHONY: build test app install uninstall snapshot clean

build:          ## Debug build of the binary.
	swift build

test:           ## Unit tests.
	swift test

app:            ## Release build of build/Claude Profiles.app.
	scripts/bundle.sh

install: app    ## Install into ~/Applications (PREFIX=...) and start it.
	scripts/install.sh

uninstall:      ## Remove the app; profiles and Claude data stay.
	scripts/install.sh --uninstall

snapshot: build ## Draw the menu window to build/menu.png with your real profiles.
	mkdir -p build
	"$$(swift build --show-bin-path)/ClaudeProfiles" --snapshot build/menu.png

clean:
	rm -rf .build build
