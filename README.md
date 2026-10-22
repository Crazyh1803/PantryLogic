# Pantry Logic

Smart recipe ingestion, cadence-driven meal planning, and dynamic grocery lists.

Flutter package: pantry_logic. Android/Linux application ID: com.appsbydan.pantrylogic.

## Open and run

Double-click `Open-Pantry-Logic.cmd` in Windows Explorer. It resolves packages, configures the local Flutter and Android SDK paths, and opens this project in Android Studio with the shared Pantry Logic run configuration.

The launcher saves diagnostics to `%TEMP%\PantryLogic-launch.log`, including the project folder and any failure message. It uses Windows PowerShell directly so it also works when PowerShell is missing from PATH.

The launcher uses the portable SDKs under `../../work` when present, then falls back to Flutter and Android Studio installed on the system. Set `STUDIO_EXE` if Android Studio is installed in a non-standard location.

For a relocated checkout, it also discovers portable tools beside the configured Flutter SDK and reuses their existing Studio properties. When Android Gradle is linked, it removes the manually registered Java root module that conflicts with Gradle compilation. It selects the shared Flutter `Pantry Logic` configuration when the old Android `app` configuration was selected.

The launcher uses the ignored project-local `.pub-cache` so Android plugin sources and build outputs stay on the same Windows drive. After changing this cache setting, close Studio completely and reopen it with `Open-Pantry-Logic.cmd` so package resolution inherits the new path. For direct Flutter commands, set `$env:PUB_CACHE = Join-Path $PWD '.pub-cache'` first.

From PowerShell, `Build.ps1` supports `-Action test`, `apk`, `aab`, `run`, or `studio`. APK output is under `build/app/outputs/flutter-apk/`; a signed release AAB requires the private configuration described in `android/RELEASE_SIGNING.md` and is written under `build/app/outputs/bundle/release/`.

If Flutter is absent from PATH, the launcher also reads its existing path from `android/local.properties`. Before building or opening Studio, it repairs the known Flutter `DeeplinkTest.kt` private Gradle JUnit import using Kotlin's existing test API. This updates that SDK test source only when the affected code is present; it keeps tests enabled. For an already-open Studio session, run `./tools/Repair-FlutterGradleTests.ps1 -FlutterRoot '<your Flutter SDK directory>'` once, then retry the build. Repeat after replacing an affected SDK.

## Build this checkout in Android Studio (Windows)

Pull the latest `main`, then install/update Flutter stable and the Flutter/Dart plugins in Android Studio. Use an SDK compatible with `pubspec.lock` (Dart 3.11 or newer); if locked SDK packages conflict, update Flutter rather than deleting the lockfile. Enable Windows Developer Mode for Flutter plugin symlinks. Install Android SDK Platform 37 through Studio's SDK Manager and accept the Android SDK licenses with `flutter doctor --android-licenses`. Gradle's checked-in daemon configuration requests Java 25; allow Studio/Gradle to provision that toolchain, or install it locally.

Close Studio and double-click `Open-Pantry-Logic.cmd`. The launcher resolves the locked packages, prepares missing Gradle wrapper files and local SDK properties, and opens the repository root with the shared **Pantry Logic** Flutter run configuration. Select your phone/emulator and click Run. The generated SDK paths and local caches stay ignored by Git.

Alternatively, from PowerShell in the repository root:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1 -Action test
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build.ps1 -Action apk
```

The test action runs the Flutter suite and all five standalone core/AI/import suites. The APK action produces `build/app/outputs/flutter-apk/app-debug.apk`; install it to use the Gemini and pasted-recipe fixes. The Studio launcher uses the same setup; it prepares configuration without compiling an APK. No API keys or release-signing files are included in Git.

## Install and migrate

Install ../PantryLogic-debug.apk. Its new application ID installs separately from Hearth. Export a backup from the old app, restore it in Pantry Logic, and re-enter AI keys/model selections. Do not remove the old app until you have checked the restored data. API keys are excluded from backups; the backup format remains compatible.

Restoring a backup merges it with local data. Matching pantry names and units use the quantity from the backup.

See ../PantryLogic-update-notes.md for rename coverage, migration steps and verification. The source archive is ../PantryLogic-source.zip.

## Features

Recipes, pantry inventory, planning and shopping lists are stored locally. Pantry items are deducted from shopping lists, and AI composition can be restricted to pantry ingredients. Pantry photos can be reviewed and added using Gemini, OpenAI, Claude or Grok. Recipe import accepts URL, text/captions and screenshots with combined notes. Optional fallback sends inputs to configured backup providers. All AI configuration is under Settings > AI.

Menus span 1-14 days with selectable shopping dates, family participants and guests. Monday-Sunday protein allowances apply across separate menus. Settings also controls cooldowns, sides, equipment, region/stores, aisle order and metric/US/UK measurements with smart cups/spoons. Inaccessible social video still requires a caption or screenshot.

## Verification

Tests: test/core_checks.dart, test/ai_checks.dart, test/feature_checks.dart, test/round2_checks.dart, test/ingestion_checks.dart, test/app_test.dart and test/runtime_smoke.dart. See VALIDATION.md for completed checks and host limitations.
