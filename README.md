# MND Standalone Builder

Turn your Meander quest into a standalone app for any platform.

## Quick Start

1. **Fork this repository** (or click "Use this template")
2. **Replace `assets/quest.mnd`** with your quest file
3. **Go to Actions** tab → "Build Standalone App" → "Run workflow"
4. Fill in your app name, package name, and pick a platform
5. **Download your app** from the workflow artifacts

## Supported Platforms

| Platform | Runner | Output |
|----------|--------|--------|
| Android APK | ubuntu-latest | `.apk` |
| Android AAB | ubuntu-latest | `.aab` (Google Play) |
| Web | ubuntu-latest | HTML/JS bundle |
| Windows | windows-latest | `.exe` |
| Linux | ubuntu-latest | binary bundle |

## Custom App Icon

Add a `ICON_PNG_B64` repository secret with your Base64-encoded PNG icon (minimum 1024x1024). The workflow will generate launcher icons for all platforms.

## Android Signing (Google Play)

Add these repository secrets for Google Play AAB signing:
- `KEYSTORE_B64` — Base64-encoded `.jks` keystore file

## License

MIT
