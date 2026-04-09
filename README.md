# Mac Cache Cleaner

A lightweight macOS desktop app to clear common cache folders, including developer-focused caches.

## Included cache targets

- User cache: `~/Library/Caches`
- User logs: `~/Library/Logs`
- Xcode:
  - `~/Library/Developer/Xcode/DerivedData`
  - `~/Library/Developer/Xcode/Archives`
  - `~/Library/Developer/Xcode/iOS DeviceSupport`
- Android Studio caches: `~/Library/Caches/Google/AndroidStudio*`
- Gradle cache: `~/.gradle/caches`
- npm cache: `~/.npm`
- Yarn cache: `~/.yarn`
- CocoaPods cache: `~/.cocoapods`

## Run

```bash
cd "/Users/abdulsamadkhan/Work/mac-cache-cleaner"
python3 app.py
```

## Built macOS app

After packaging, the app bundle is at:

- `dist/Mac Cache Cleaner.app`

You can open it with:

```bash
open "dist/Mac Cache Cleaner.app"
```

## How to use

1. Click **Scan Sizes** to estimate current cache usage.
2. Keep **recommended** targets selected (or choose all).
3. Click **Clear Selected** and confirm.

## Notes

- The app deletes folder contents, not the folder itself.
- Some files may be skipped if macOS denies access.
- For large cleanups, close Xcode/Android Studio first.
# mac-cache-cleaner
