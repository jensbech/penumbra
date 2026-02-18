build:
    swift build -c release
    mkdir -p penumbra.app/Contents/MacOS
    cp .build/release/penumbra penumbra.app/Contents/MacOS/penumbra
    cp Resources/Info.plist penumbra.app/Contents/Info.plist

install: build
    cp -r penumbra.app /Applications/penumbra.app
