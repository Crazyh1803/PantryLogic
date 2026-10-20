# Recipe and shopping integrity
- Add a shared ingredient identity/category registry with conservative aliases and validation; keep legacy JSON compatible using derived stable IDs.
- Bound offline parsing to ingredient and method sections; reject instruction-like ingredients and malformed amounts in AI decoding.
- Aggregate by canonical identity and compatible base units, deterministic categories and ordering. Retain checked keys through alias/unit normalization.
- Persist explicit shopping overrides/manual items in plan JSON and apply after pantry subtraction. Regeneration remains a pure calculation; edits and checks survive save/reload and backup.
- Add parser, aggregation and persistence regressions; run ak-test, analyzer and ak-review.

## Implementation and verification
- Shared catalog applies to all ingredients, with UK/US/German aliases across produce, dairy, seafood, poultry, meat and staples. Whole-name matching preserves distinct forms (e.g. canned tomatoes, coriander seeds, beef stock).
- Known foods inherit their canonical aisle; unfamiliar foods retain a supported source aisle. Conflicting source aisles resolve deterministically when consolidating. Mass, volume and unspecified quantities stay separate; no density conversion is guessed.
- Shopping overrides and manual additions persist in plan JSON and backup/restore. Meal replacement, side removal, date selection and same-week regeneration retain checks and explicit edits. Unspecified amounts remain on lists unless covered by pantry.
- Regression tests include SQLite save/reload and backup/restore, repeated generation, multiple aliases/categories, unit conversion, instruction rejection and malformed amounts. Linux tests fall back to the runtime SQLite library when the unversioned development-library name is absent.
- Validation: ak-test runs flutter test plus ingestion_checks.dart, ai_checks.dart, feature_checks.dart and round2_checks.dart. flutter analyze --no-pub and git diff --check are also run.
- Initial external review attempts were unavailable because Claude was logged out; authenticated follow-up results are recorded below.
- APK build unavailable: flutter build apk --debug --no-pub reports “No Android SDK found”.

## Authenticated review follow-up — October 16, 2026
- Claude login verified. First authenticated review requested changes.
- Fixed ambiguous pepper/paprika mappings so spices cannot merge with bell peppers; explicit German color-qualified paprika aliases remain produce.
- Kept basic model/legacy JSON validation compatible, with strict food-name validation at new ingestion and manual-entry boundaries.
- Regeneration is pure. Normalize checked keys on load/save, prune absent checks and source-less overrides on save, respect pantry coverage, and expose “Use recipe amount” to reset edits. Manual additions remain independent of menu demand.
- Moved shopping-edit controllers into a stateful dialog so disposal follows route lifetime. Zero amounts are rejected; only a blank amount means unspecified.
- Ambiguous caption ingredient subgroups defer to structured ingestion; method quote cleanup and blank AI amounts are handled.
- Added regressions for pepper/paprika collisions, legacy persistence, override removal/reset/pantry behavior, pure rendering, caption groups, and dialog validation/disposal. sqlite3 already is a direct dependency; no dependency change was needed.

- Focused second authenticated review returned APPROVE (`.ai/reviews/20261016-083746-claude.md`). Its remaining medium suggestions were also fixed: preserve checks against pantry-independent demand, preserve the full stored list, transfer checks when resetting edited units, and distinguish ingredient subgroup labels from bulleted methods.
- Final verification: 24 Flutter tests passed, all existing ingestion/provider/planning regression scripts passed, static analysis reported no issues, and git diff --check passed.
