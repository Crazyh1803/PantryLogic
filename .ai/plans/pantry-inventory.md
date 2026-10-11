# Pantry inventory

## Goal

Add a local pantry inventory that removes available quantities from shopping lists, optionally constrains AI-composed recipes to pantry ingredients, and can be populated from a camera or gallery image.

## Design

- Add a `PantryItem` model and a versioned `pantry_items` SQLite table. Keep quantities and units so shopping subtraction is exact when units are compatible; name-only items suppress matching unspecified ingredients.
- Extend `GroceryAggregator` with pantry subtraction after recipe consolidation, preserving the existing canonical-name and unit conversion rules. Name-only stock covers only unmeasured recipe needs; measured needs require compatible measured stock.
- Add an AI pantry-image extraction operation with a small structured schema returning ingredient name, quantity, and unit. Reuse provider transport, fallback, size limits, and error handling.
- Add a Pantry destination with manual add/edit/delete and camera/gallery import. Review detected items before saving.
- Add an "only pantry ingredients" compose option. Pass the pantry names as required allowed ingredients and validate the returned recipe locally so providers cannot silently ignore the constraint.
- Include pantry inventory in local backup/restore without breaking version-1 backups.

## Verification

- Unit tests for pantry subtraction, incompatible units, and constrained recipe validation.
- Database tests where feasible through the existing test harness.
- Run `ak-test`, then `ak-review`; fix all HIGH and justified MED findings.
