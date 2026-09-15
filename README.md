# Pantry Logic

Smart recipe ingestion, cadence-driven meal planning, and dynamic grocery lists.

Flutter package: pantry_logic. Android/Linux application ID: com.appsbydan.pantrylogic.

## Open and run

Open ../Open-Pantry-Logic.cmd in Windows Explorer, or open this pantry_logic directory in Android Studio. Select the Pantry Logic run configuration. Build.ps1 supports -Action test, apk or run from a normal PowerShell session.

The configured Flutter SDK is ../../work/toolchain/flutter and Android SDK is ../../work/android-sdk. Keep the workspace toolchain directory and its linked SDK tools.

## Install and migrate

Install ../PantryLogic-debug.apk. Its new application ID installs separately from Hearth. Export a backup from the old app, restore it in Pantry Logic, and re-enter AI keys/model selections. Do not remove the old app until you have checked the restored data. API keys are excluded from backups; the backup format remains compatible.

See ../PantryLogic-update-notes.md for rename coverage, migration steps and verification. The source archive is ../PantryLogic-source.zip.

## Features

Recipes, planning and shopping lists are stored locally. Import accepts URL, text/captions and screenshots with combined notes. Structured captions can import without a key; other text/images use Gemini, OpenAI, Claude or Grok. Optional fallback sends inputs to configured backup providers. All AI configuration is under Settings > AI.

Menus span 1-14 days with selectable shopping dates, family participants and guests. Monday-Sunday protein allowances apply across separate menus. Settings also controls cooldowns, sides, equipment, region/stores, aisle order and metric/US/UK measurements with smart cups/spoons. Inaccessible social video still requires a caption or screenshot.

## Verification

Tests: test/core_checks.dart, test/ai_checks.dart, test/feature_checks.dart, test/round2_checks.dart, test/ingestion_checks.dart, test/app_test.dart and test/runtime_smoke.dart. See VALIDATION.md for completed checks and host limitations.
