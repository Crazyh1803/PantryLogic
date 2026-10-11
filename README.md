# Pantry Logic

Smart recipe ingestion, cadence-driven meal planning, and dynamic grocery lists.

Flutter package: pantry_logic. Android/Linux application ID: com.appsbydan.pantrylogic.

## Open and run

Double-click `Open-Pantry-Logic.cmd` in Windows Explorer. It resolves packages, configures the local Flutter and Android SDK paths, and opens this project in Android Studio with the shared Pantry Logic run configuration.

The launcher uses the portable SDKs under `../../work` when present, then falls back to Flutter and Android Studio installed on the system. Set `STUDIO_EXE` if Android Studio is installed in a non-standard location.

From PowerShell, `Build.ps1` supports `-Action test`, `apk`, `aab`, `run`, or `studio`. APK output is under `build/app/outputs/flutter-apk/`; a signed release AAB requires the private configuration described in `android/RELEASE_SIGNING.md` and is written under `build/app/outputs/bundle/release/`.

## Install and migrate

Install ../PantryLogic-debug.apk. Its new application ID installs separately from Hearth. Export a backup from the old app, restore it in Pantry Logic, and re-enter AI keys/model selections. Do not remove the old app until you have checked the restored data. API keys are excluded from backups; the backup format remains compatible.

Restoring a backup merges it with local data. Matching pantry names and units use the quantity from the backup.

See ../PantryLogic-update-notes.md for rename coverage, migration steps and verification. The source archive is ../PantryLogic-source.zip.

## Features

Recipes, pantry inventory, planning and shopping lists are stored locally. Pantry items are deducted from shopping lists, and AI composition can be restricted to pantry ingredients. Pantry photos can be reviewed and added using Gemini, OpenAI, Claude or Grok. Recipe import accepts URL, text/captions and screenshots with combined notes. Optional fallback sends inputs to configured backup providers. All AI configuration is under Settings > AI.

Menus span 1-14 days with selectable shopping dates, family participants and guests. Monday-Sunday protein allowances apply across separate menus. Settings also controls cooldowns, sides, equipment, region/stores, aisle order and metric/US/UK measurements with smart cups/spoons. Inaccessible social video still requires a caption or screenshot.

## Verification

Tests: test/core_checks.dart, test/ai_checks.dart, test/feature_checks.dart, test/round2_checks.dart, test/ingestion_checks.dart, test/app_test.dart and test/runtime_smoke.dart. See VALIDATION.md for completed checks and host limitations.
