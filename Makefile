.PHONY: build run play test check-shader app smoke smoke-realm smoke-menu clean

build:
	swift build

run:
	swift run NullmereLauncher

# Plays in the realm served on this Mac by scripts/serve-realm.sh nullmere.
play:
	NULLMERE_REALM=http://127.0.0.1:3000/nullmere swift run NullmereLauncher

test:
	swift test

check-shader:
	scripts/check-shader.sh

app:
	scripts/build-app.sh

smoke: app
	scripts/smoke-test-app.sh

# Needs a SpacetimeDB server running on this Mac (docs/DEVELOPING.md).
smoke-realm: build
	scripts/smoke-test-rebuilt.sh

smoke-menu: build
	scripts/smoke-test-launcher-menu.sh

clean:
	rm -rf .build build
