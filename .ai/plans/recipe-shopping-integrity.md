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
- External review unavailable: ak-escalate design and two ak-review attempts report “Not logged in · Please run /login”. No APPROVE verdict was obtained.
- APK build unavailable: flutter build apk --debug --no-pub reports “No Android SDK found”.
