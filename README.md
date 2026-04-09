# Mac Cache Cleaner

macOS cache-cleaning utility with two desktop implementations in this repo:
- `app.py`: Python + Tkinter app
- `SwiftUIMacCacheCleaner/`: SwiftUI app (Swift Package)

## What it cleans

The apps target common cache/log folders, including:
- `~/Library/Caches`
- `~/Library/Logs`
- `~/Library/Developer/Xcode/DerivedData`
- `~/Library/Developer/Xcode/Archives`
- `~/Library/Developer/Xcode/iOS DeviceSupport`
- `~/Library/Caches/Google/AndroidStudio*`
- `~/.gradle/caches`
- `~/.npm`
- `~/.yarn`
- `~/.cocoapods`

## Run the Python app

```bash
cd "/Users/abdulsamadkhan/Work/mac-cache-cleaner"
python3 app.py
```

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
2. Keep recommended targets selected (or use **Select All**).
3. Click **Clear Selected** and confirm.

## Safety notes

- Only contents are removed; top-level target folders are retained.
- Files may be skipped if macOS denies permission.
- Close Xcode/Android Studio before large cleanups for best results.
