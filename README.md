# Mac Cache Cleaner

macOS cache-cleaning utility built as a native SwiftUI desktop app.

## What it cleans

The app dynamically discovers safe cache folders on your Mac and only shows folders that actually exist.
It supports:
- `Strict` mode: conservative cache-only discovery
- `Balanced` mode: broader cache/log/temp discovery

## Build and run the SwiftUI app

```bash
cd "/Users/abdulsamadkhan/Work/mac-cache-cleaner/SwiftUIMacCacheCleaner"
swift run
```

To build an app bundle:

```bash
cd "/Users/abdulsamadkhan/Work/mac-cache-cleaner/SwiftUIMacCacheCleaner"
./build_app.sh
open "dist/Mac Cache Cleaner SwiftUI.app"
```

## Usage

1. Click **Scan Sizes**.
2. Pick **Strict** or **Balanced** discovery mode.
3. Review target inclusion reasons shown for each folder.
4. Keep recommended targets selected (or use **Select All**).
5. Click **Clear Selected** and confirm.

## Safety notes

- Only contents are removed; top-level target folders are retained.
- Files may be skipped if macOS denies permission.
- Discovery is scoped to user-home locations with protected top-level folders excluded.
