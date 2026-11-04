.PHONY: app install whisper test test-capture smoke release clean

app:
	./scripts/build-app.sh

install: app
	rm -rf /Applications/OpenRecord.app
	cp -R build/OpenRecord.app /Applications/

whisper:
	./scripts/setup-whisper.sh

test:
	swift test

test-capture:
	OPENRECORD_CAPTURE_TESTS=1 swift test --filter ScreenRecorderTests

smoke: app
	python3 scripts/mcp_smoke_test.py build/OpenRecord.app/Contents/MacOS/openrecord-mcp

release:
	./scripts/release.sh

clean:
	rm -rf .build build dist
