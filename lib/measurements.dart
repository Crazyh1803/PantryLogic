import 'models.dart';
import 'grocery_aggregator.dart';

class Measurements {
  static String number(double value, {bool fractions = false}) {
    if (fractions) {
      final whole = value.floor(), part = value - whole;
      final values = {
        0.125: '⅛',
        0.25: '¼',
        1 / 3: '⅓',
        0.5: '½',
        2 / 3: '⅔',
        0.75: '¾',
      };
      for (final e in values.entries) {
        if ((part - e.key).abs() < 0.006) {
          return '${whole == 0 ? '' : whole}${e.value}';
        }
      }
    }
    if ((value - value.round()).abs() < 0.006) return '${value.round()}';
    if (value > 0 && value < 0.01) return '<0.01';
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static String format(
    Ingredient i, {
    required String system,
    required String volumeStyle,
  }) {
    if (!i.quantitySpecified) return 'as needed';
    final c = GroceryAggregator.conversions[normalized(i.unit)];
    if (c == null) return '${number(i.quantity, fractions: true)} ${i.unit}';
    final base = i.quantity * c.$2;
    if (c.$1 == 'g') {
      if (system == 'metric') {
        return base >= 1000 ? '${number(base / 1000)} kg' : '${number(base)} g';
      }
      final ounces = base / 28.349523125;
      return ounces >= 16
          ? '${number(ounces / 16, fractions: true)} lb'
          : '${number(ounces, fractions: true)} oz';
    }
    if (c.$1 != 'ml') return '${number(base, fractions: true)} ${c.$1}';
    if (volumeStyle == 'ml') {
      return base >= 1000 ? '${number(base / 1000)} L' : '${number(base)} mL';
    }
    final cup = system == 'us'
        ? 236.5882365
        : system == 'uk'
        ? 284.130625
        : 250.0;
    final tbsp = system == 'us'
        ? 14.78676478125
        : system == 'uk'
        ? 17.7581640625
        : 15.0;
    final tsp = system == 'us'
        ? 4.92892159375
        : system == 'uk'
        ? 5.919388020833333
        : 5.0;
    final label = system == 'us'
        ? 'US'
        : system == 'uk'
        ? 'UK imperial'
        : 'metric';
    if (base >= cup / 4 - 0.01) {
      return '${number(base / cup, fractions: true)} $label cup';
    }
    if (base >= tbsp - 0.01) {
      return '${number(base / tbsp, fractions: true)} $label tbsp';
    }
    return '${number(base / tsp, fractions: true)} $label tsp';
  }
}
