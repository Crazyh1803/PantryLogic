import 'models.dart';

List<Recipe> starterSides() => [
  Recipe(
    title: 'Lemon green beans',
    protein: 'vegetarian',
    isSide: true,
    ingredients: [
      Ingredient(
        name: 'green beans',
        quantity: 300,
        unit: 'g',
        aisle: 'Produce',
        isPerishable: true,
      ),
      Ingredient(
        name: 'lemon',
        quantity: 0.5,
        unit: 'whole',
        aisle: 'Produce',
        isPerishable: true,
      ),
      Ingredient(name: 'olive oil', quantity: 15, unit: 'ml'),
    ],
    instructions: [
      'Steam trimmed green beans for 5–7 minutes until tender.',
      'Toss with olive oil and lemon juice.',
    ],
  ),
  Recipe(
    title: 'Fluffy basmati rice',
    protein: 'vegetarian',
    isSide: true,
    ingredients: [
      Ingredient(name: 'basmati rice', quantity: 150, unit: 'g'),
      Ingredient(name: 'water', quantity: 300, unit: 'ml'),
    ],
    instructions: [
      'Rinse rice. Add water and bring to a boil.',
      'Cover, reduce to low and cook for 12 minutes. Turn off heat and rest covered for 5 minutes.',
    ],
  ),
  Recipe(
    title: 'Cucumber dill salad',
    protein: 'vegetarian',
    isSide: true,
    ingredients: [
      Ingredient(
        name: 'cucumber',
        quantity: 1,
        unit: 'whole',
        aisle: 'Produce',
        isPerishable: true,
      ),
      Ingredient(
        name: 'yogurt',
        quantity: 100,
        unit: 'g',
        aisle: 'Dairy',
        isPerishable: true,
      ),
      Ingredient(
        name: 'dill',
        quantity: 5,
        unit: 'g',
        aisle: 'Produce',
        isPerishable: true,
      ),
    ],
    instructions: [
      'Slice cucumber thinly and chop dill.',
      'Toss with yogurt and serve chilled.',
    ],
  ),
  Recipe(
    title: 'Roasted paprika carrots',
    protein: 'vegetarian',
    isSide: true,
    ingredients: [
      Ingredient(
        name: 'carrots',
        quantity: 350,
        unit: 'g',
        aisle: 'Produce',
        isPerishable: true,
      ),
      Ingredient(name: 'olive oil', quantity: 15, unit: 'ml'),
      Ingredient(name: 'paprika', quantity: 2, unit: 'g', aisle: 'Spices'),
    ],
    instructions: [
      'Heat oven to 200°C. Cut carrots into even sticks.',
      'Toss with oil and paprika. Roast for 25 minutes, turning halfway.',
    ],
  ),
];
