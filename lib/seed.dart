import 'models.dart';

List<Recipe> seedRecipes() {
  Ingredient ingredient(
    String n,
    double q,
    String u,
    String a, [
    bool fresh = false,
  ]) =>
      Ingredient(name: n, quantity: q, unit: u, aisle: a, isPerishable: fresh);
  final oil = ingredient('olive oil', 1, 'tbsp', 'Pantry');
  final garlic = ingredient('garlic', 2, 'clove', 'Produce', true);
  return [
    Recipe(
      title: 'Lemon chicken & herby rice',
      protein: 'chicken',
      ingredients: [
        ingredient('chicken breast', 300, 'g', 'Meat'),
        ingredient('rice', 150, 'g', 'Pantry'),
        ingredient('lemon', 1, 'whole', 'Produce'),
        ingredient('parsley', 15, 'g', 'Produce', true),
        garlic,
        oil,
      ],
      instructions: [
        'Cook rice in water according to the packet.',
        'Cut chicken into strips. Heat oil and cook chicken with crushed garlic until its center reaches 74°C.',
        'Add lemon juice and chopped parsley. Serve over rice.',
      ],
    ),
    Recipe(
      title: 'Chickpea parsley bowls',
      protein: 'vegetarian',
      ingredients: [
        ingredient('cooked chickpeas', 400, 'g', 'Pantry'),
        ingredient('couscous', 150, 'g', 'Pantry'),
        ingredient('parsley', 15, 'g', 'Produce', true),
        ingredient('lemon', 1, 'whole', 'Produce'),
        oil,
      ],
      instructions: [
        'Cover couscous with boiling water according to the packet and let stand.',
        'Drain chickpeas and warm in a pan with olive oil.',
        'Fluff couscous and fold in chickpeas, chopped parsley and lemon juice.',
      ],
    ),
    Recipe(
      title: 'Ground beef tacos',
      protein: 'beef',
      targetFrequencyDays: 18,
      ingredients: [
        ingredient('ground beef', 300, 'g', 'Meat'),
        ingredient('tortillas', 6, 'whole', 'Bakery'),
        ingredient('tomato', 2, 'whole', 'Produce'),
        ingredient('cilantro', 15, 'g', 'Produce', true),
        ingredient('cumin', 1, 'tsp', 'Spices'),
        oil,
      ],
      instructions: [
        'Heat oil and brown beef with cumin until it reaches 71°C.',
        'Dice tomatoes and chop cilantro.',
        'Warm tortillas, fill with beef and finish with tomato and cilantro.',
      ],
    ),
    Recipe(
      title: 'Cilantro lime salmon',
      protein: 'fish',
      ingredients: [
        ingredient('salmon', 300, 'g', 'Seafood'),
        ingredient('rice', 150, 'g', 'Pantry'),
        ingredient('cilantro', 15, 'g', 'Produce', true),
        ingredient('lime', 1, 'whole', 'Produce'),
        oil,
      ],
      instructions: [
        'Cook rice according to the packet.',
        'Brush salmon with oil and bake at 200°C until the thickest part reaches 63°C.',
        'Top with lime juice and chopped cilantro; serve with rice.',
      ],
    ),
    Recipe(
      title: 'Chicken & spinach skillet',
      protein: 'chicken',
      ingredients: [
        ingredient('chicken breast', 300, 'g', 'Meat'),
        ingredient('spinach', 100, 'g', 'Produce', true),
        ingredient('pasta', 160, 'g', 'Pantry'),
        ingredient('cream', 100, 'ml', 'Dairy'),
        garlic,
        oil,
      ],
      instructions: [
        'Cook pasta according to the packet, reserving a little cooking water.',
        'Slice chicken and cook in oil with garlic until the center reaches 74°C.',
        'Stir in cream and spinach until wilted, then toss with pasta and a splash of pasta water.',
      ],
    ),
    Recipe(
      title: 'Spinach & white bean stew',
      protein: 'vegetarian',
      ingredients: [
        ingredient('cooked white beans', 400, 'g', 'Pantry'),
        ingredient('spinach', 100, 'g', 'Produce', true),
        ingredient('canned tomatoes', 400, 'g', 'Pantry'),
        garlic,
        oil,
      ],
      instructions: [
        'Soften crushed garlic in olive oil over medium heat.',
        'Add drained beans and canned tomatoes; simmer for 15 minutes.',
        'Stir in spinach until wilted. Season to taste.',
      ],
    ),
    Recipe(
      title: 'Roasted vegetable couscous',
      protein: 'vegetarian',
      ingredients: [
        ingredient('carrot', 2, 'whole', 'Produce'),
        ingredient('zucchini', 1, 'whole', 'Produce'),
        ingredient('couscous', 150, 'g', 'Pantry'),
        oil,
      ],
      instructions: [
        'Cut vegetables into bite-size pieces, toss with oil, and roast at 200°C for 25–30 minutes.',
        'Prepare couscous according to the packet.',
        'Fluff couscous and toss with roasted vegetables.',
      ],
    ),
    Recipe(
      title: 'Paprika chicken traybake',
      protein: 'chicken',
      ingredients: [
        ingredient('chicken breast', 300, 'g', 'Meat'),
        ingredient('potato', 400, 'g', 'Produce'),
        ingredient('paprika', 1, 'tsp', 'Spices'),
        oil,
      ],
      instructions: [
        'Cut potatoes into small wedges. Toss with oil and paprika; roast at 200°C for 15 minutes.',
        'Add chicken and roast another 20–25 minutes, until chicken reaches 74°C and potatoes are tender.',
      ],
    ),
    Recipe(
      title: 'Ginger chicken noodles',
      protein: 'chicken',
      ingredients: [
        ingredient('chicken breast', 300, 'g', 'Meat'),
        ingredient('noodles', 160, 'g', 'Pantry'),
        ingredient('ginger', 15, 'g', 'Produce', true),
        ingredient('soy sauce', 2, 'tbsp', 'Pantry'),
        oil,
      ],
      instructions: [
        'Cook noodles according to the packet.',
        'Slice chicken and stir-fry in oil with grated ginger until it reaches 74°C.',
        'Toss with noodles and soy sauce.',
      ],
    ),
    Recipe(
      title: 'Beef & broccoli rice',
      protein: 'beef',
      ingredients: [
        ingredient('beef strips', 300, 'g', 'Meat'),
        ingredient('broccoli', 250, 'g', 'Produce'),
        ingredient('rice', 150, 'g', 'Pantry'),
        ingredient('soy sauce', 2, 'tbsp', 'Pantry'),
        oil,
      ],
      instructions: [
        'Cook rice according to the packet.',
        'Stir-fry broccoli in oil with a splash of water until tender.',
        'Add beef strips and cook thoroughly; add soy sauce and serve over rice.',
      ],
    ),
    Recipe(
      title: 'Tomato baked cod',
      protein: 'fish',
      ingredients: [
        ingredient('cod', 300, 'g', 'Seafood'),
        ingredient('canned tomatoes', 400, 'g', 'Pantry'),
        ingredient('potato', 400, 'g', 'Produce'),
        oil,
      ],
      instructions: [
        'Dice potatoes, toss with oil, and roast at 200°C for 25 minutes.',
        'Place cod over tomatoes in a baking dish. Bake at 200°C until fish reaches 63°C, about 15–20 minutes.',
        'Serve with the potatoes.',
      ],
    ),
    Recipe(
      title: 'Mushroom omelette',
      protein: 'vegetarian',
      ingredients: [
        ingredient('eggs', 4, 'whole', 'Dairy'),
        ingredient('mushrooms', 200, 'g', 'Produce'),
        ingredient('cheese', 50, 'g', 'Dairy'),
        oil,
      ],
      instructions: [
        'Slice mushrooms and sauté in oil until browned.',
        'Beat eggs, pour over mushrooms and cook gently until set.',
        'Sprinkle with grated cheese and fold to serve.',
      ],
    ),
  ];
}
