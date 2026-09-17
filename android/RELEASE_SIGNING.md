# Pantry Logic release signing

Release bundles use the private upload key configured in `android/key.properties`.
That file and the keystore are intentionally excluded from Git.

The local signing backup is stored in:

`C:\Users\dwhit\Documents\Pantry Logic Signing`

Back up that entire folder in a secure location. The upload key is required to
publish future updates to the same Google Play application.

Build a signed Android App Bundle from the Flutter project root with:

```powershell
flutter build appbundle --release
```

The bundle is written to:

`build\app\outputs\bundle\release\app-release.aab`
