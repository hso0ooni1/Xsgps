# XsGPS Android — non-root beta

Standalone Android **test-location** app (not a modified HUDURY APK). Features:
- Coordinates and geocoder search, tappable OpenStreetMap map
- 50 saved locations, press to select and long-press to delete
- Slow constrained random movement (0–100 m radius)
- Standard Android mock GPS provider, foreground service and stop control
- Optional Android license activation using existing XsGPS worker /activate and /verify endpoints.

## Install and use
1. Download XsGPS-Android-debug.apk from the GitHub Actions build artifact.
2. Install the APK. Grant precise location.
3. Enable Android Developer options, then select XsGPS Android under **Select mock location app**.
4. Enter coordinates (or select a point on the map), set movement and click start.
5. Stop from the application to remove its mock GPS provider.

This is a **debug beta**, unlocked for direct testing while the updated worker is not yet deployed. Release builds require a verified license. Do not treat this as a stealth or universally compatible GPS injector: Android exposes mock-location state to apps. This build never modifies another APK, copies device identifiers, hides mock-location flags, or bypasses app integrity checks.

## Code panel deployment
To enable Android codes, publish the separately supplied XsGpS-Worker-iOS-Android.js in your existing Cloudflare Worker, retaining the DB binding and ADMIN_KEY. Backup D1 first and call the authenticated /admin/setup migration. The currently deployed worker has **not** been verified to support Android.

The Android package intentionally does not request root, accessibility, all-files access, or background location. Map tiles require internet. License code and bookmarks are stored locally in app-private preferences; coordinates/bookmarks are never sent to the license API.
