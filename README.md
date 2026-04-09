# Mac Cache Cleaner

macOS cache-cleaning utility built as a native SwiftUI desktop app.

## What it cleans

The app dynamically discovers safe cache folders on your Mac and only shows folders that actually exist.
It supports:
- `Ultra Safe` mode: only `~/Library/Caches` (default)
- `Strict` mode: conservative cache-only discovery (adds app container caches and cautious Xcode/Simulator cache roots)
- `Balanced` mode: broader cache/log/temp discovery
- `Developer Deep Clean` mode: adds opt-in developer caches across multiple ecosystems (for example Gradle, npm/yarn/pnpm, pip/poetry, Android Studio, JetBrains, and extra Xcode build caches)

This means the app is useful for both:
- general Mac users who want safe cleanup (`Ultra Safe`, `Strict`, or `Balanced`)
- developers who also want deeper toolchain cleanup (`Developer Deep Clean`)

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
2. Pick **Ultra Safe**, **Strict**, or **Balanced** discovery mode.
3. Review target inclusion reasons shown for each folder.
4. Keep recommended targets selected (or use **Select All**).
5. Click **Dry Run** to preview estimated reclaimable space and inaccessible folders.
6. Click **Clear Selected** and confirm.
7. Review the cleanup report in the footer (removed, skipped, inaccessible, estimated freed).
8. If a scan/cleanup takes too long, click **Cancel** to stop the active operation.

## Safety notes

- Only contents are removed; top-level target folders are retained.
- Files may be skipped if macOS denies permission.
- Discovery is allowlisted to known cache/log/temp roots (for example `~/Library/Caches`, app container cache/log roots, and developer caches like DerivedData).
- A second runtime safety check blocks cleanup of any path outside approved cache/log/temp locations, even if it was somehow discovered.
- Personal files and normal app data locations are intentionally not targeted.
