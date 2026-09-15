# Validation — September 15, 2026

## Pantry Logic rename

- Package name is pantry_logic; Android/Linux ID is com.appsbydan.pantrylogic. Requested description and platform/UI metadata are updated. MainActivity is under kotlin/com/appsbydan/pantrylogic. Searches of active source/configuration found no old package imports or application namespaces.
- Fresh Android debug build passed: 220 Gradle tasks executed, 5 up-to-date. APK manifest inspection confirms Pantry Logic, com.appsbydan.pantrylogic, and com.appsbydan.pantrylogic.MainActivity. Installed and opened on the API 35 emulator alongside the previous app.
- All 103 core/provider/ingestion/measurement/planning assertions passed after the rename. SQLite engine CRUD and backup/restore passed. Direct Dart analysis: zero errors and zero warnings.
- The renamed header was visually checked at 360 dp and 130% text size with no overflow; emulator display settings were restored afterward.
- flutter clean and flutter pub get were both attempted but blocked by the Windows subprocess restriction. Generated build/package caches were preserved under work/rename-cache-backup. dart pub get --offline resolved dependencies successfully, Flutter tooling refreshed plugin metadata/registrants, and the app was compiled from fresh project build directories.
- Linux and Windows metadata were inspected; native desktop binaries were not built. Previous feature validation below remains relevant; historical references to Hearth describe the prior application identity.

## Feature validation before the rename

- Android assembleDebug passed using Java from portable Android Studio 2026.1.4, AGP 9.1.0 and Gradle 9.3.1.
- Final static analysis: no errors or warnings; style-only suggestions remain.
- 14 existing core checks passed.
- 6 mocked Gemini adapter checks passed.
- 22 new feature/provider assertions passed, covering configurable menus, family filtering, settings round trip, global/recipe/side cooldowns, legacy plans, selected shopping days, birthday timing, dimensional conversion and OpenAI/Claude/Grok/fallback parsing.
- 31 follow-up checks passed: exact 13-ingredient caption, Unicode fractions, unspecified amounts, source conflicts, offline import, smart measurements, weekly allowances across menus and week boundaries, history deduplication, replacement reservations, bounded retries, custom models, model discovery, Claude tools and OpenAI strict JSON.
- 30 ingestion checks passed: exact friendly error mapping/actions; model errors versus bad keys; API permissions versus scraping failures; no internal detail leakage; no AI calls for empty/blocked/login pages; 100-character boundary; URL plus captions/notes; offline caption fallback; JSON-LD plus context; images plus notes; actual PNG MIME/base64 through the Google SDK; structured times/notes; SDK failure fallback; missing-key recovery.
- SQLite smoke test also verifies prep/cook minutes, notes, source URL and unspecified quantities through save, reload and backup/restore.
- Updated emulator UI checks: exact caption opens review with source ambiguities; URL/Text/Image tabs; measurement dropdown fits at 360 dp and font scale 1.3. Display settings were restored. No Flutter overflow or runtime exception appeared in these checks.
- Missing-key import shows the mapped message, preserves the text and opens Settings > AI via Go to Settings.
- Final APK recovery check: an empty import reveals the caption field and Android reports that field focused; the warning remains non-blocking.
- Direct Flutter-engine SQLite smoke test passed: CRUD, history uniqueness, FK cascade, backup/restore, settings, short menus, sides, shopping selection, guests and cooldown-override data.
- Emulator APK installation and launch passed. Verified birthday prompt, three-day generation with three side dishes, shopping selection totals 22 → 16 → 9 and persistence after force-stop/relaunch. Verified Alexa manual export dialog and Settings screens.
- User confirmed repaired Android Studio opens Hearth correctly. Logs show Flutter device daemon and Dart analysis starting.

## Scope and limitations

The requested `flutter analyze --no-pub outputs/hearth` was attempted. Windows returned CreateFile access denied when Flutter tried to start git. Direct Dart analysis-server execution completed with zero errors and zero warnings; style-only infos remain. The normal Flutter command did not complete successfully.

The session approval policy blocked the live Instagram-link emulator check; blocked/empty-content handling was verified with mocked HTTP responses.

No live API key was used. Account billing, access and model availability still require the in-app connection test. Alexa direct list sync is unavailable because Amazon retired that API. Cross-dimension ingredient conversion requires the user to enter a measured equivalent; no density or piece size is invented.

The APK is debug-signed for ARM64 and x86-64. Dart subprocess restrictions in this build host prevent the normal flutter build/test orchestration, so kernel/assets were compiled directly and Gradle assembled the APK. The empty Flutter CMake setup step was disabled in that restricted build; native plugin libraries remain packaged. Normal Studio and Build.ps1 run standard Flutter commands in the user's Windows session. A Play Store release needs release signing and release validation.
