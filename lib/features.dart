part of 'main.dart';

extension _HomeFeatures on _HomeState {
  Future<void> persistSettings() async {
    await secure.write(key: 'gemini_key', value: keyField.text.trim());
    await saveAdvanced();
    await db!.setSetting('servings', '$servings');
    await db!.setSetting('model', modelField.text.trim());
    await db!.setSetting('profile', profileField.text);
    appThemeMode.value = prefs.darkMode ? ThemeMode.dark : ThemeMode.light;
    message('Settings saved.');
  }

  TextEditingController keyFor(String p) =>
      p == 'Gemini' ? keyField : providerKeys[p]!;
  TextEditingController modelFor(String p) =>
      p == 'Gemini' ? modelField : providerModelFields[p]!;
  ProviderService serviceFor(String p) => ProviderService(
    provider: p,
    apiKey: keyFor(p).text.trim(),
    model: modelFor(p).text.trim(),
  );
  Future<void> openLink(String url) async {
    try {
      if (Platform.isAndroid) {
        await const MethodChannel(
          'pantry_logic/actions',
        ).invokeMethod('openUrl', url);
      } else {
        await Clipboard.setData(ClipboardData(text: url));
        message('Link copied: $url');
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: url));
      message('No browser available. Link copied.');
    }
  }

  Widget supportLink() => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 8),
    child: TextButton(
      onPressed: () => openLink('https://buymeacoffee.com/AppsbyDan'),
      child: const Text(
        'Enjoying Pantry Logic? Buy Dan a coffee',
        style: TextStyle(fontSize: 12),
      ),
    ),
  );
  Future<void> birthdayPrompt() async {
    final now = DateTime.now();
    if (!birthdayDue(
          now,
          int.tryParse(await db!.setting('birthday_year') ?? '') ?? 0,
        ) ||
        !mounted) {
      return;
    }
    await db!.setSetting('birthday_year', '${now.year}');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('A birthday toast?'),
        content: const Text(
          'May 15 is Dan’s birthday. If Pantry Logic makes your kitchen a little happier, would you like to buy him a drink?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Maybe next year'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              openLink('https://buymeacoffee.com/AppsbyDan');
            },
            child: const Text('Buy a drink'),
          ),
        ],
      ),
    );
  }

  Future<String?> askText(String title, String value, {String? help}) async {
    final field = TextEditingController(text: value);
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: field,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(helperText: help),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, field.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Dialog route may still be animating; its controller is disposed after removal.
    Future<void>.delayed(const Duration(seconds: 1), field.dispose);
    return result;
  }

  Future<void> saveAdvanced() async {
    await db!.setSetting('preferences', prefs.encode());
    for (final p in providerKeys.keys) {
      await secure.write(
        key: '${p.toLowerCase()}_key',
        value: keyFor(p).text.trim(),
      );
      await db!.setSetting('${p}_model', modelFor(p).text.trim());
    }
  }

  Future<void> editMember([FamilyMember? member]) async {
    final name = await askText('Family member name', member?.name ?? '');
    if (name == null || name.isEmpty || !mounted) return;
    final likes = await askText(
      'What does $name like?',
      member?.likes ?? '',
      help: 'Comma-separated ingredients or cuisines',
    );
    if (likes == null || !mounted) return;
    final dislikes = await askText(
      'What does $name dislike?',
      member?.dislikes ?? '',
      help: 'Comma-separated ingredients; library matching uses these words',
    );
    if (dislikes == null) return;
    updateFeatures(() {
      if (member == null) {
        prefs.family.add(
          FamilyMember(
            DateTime.now().microsecondsSinceEpoch.toString(),
            name,
            likes,
            dislikes,
          ),
        );
      } else {
        member.name = name;
        member.likes = likes;
        member.dislikes = dislikes;
      }
    });
    await saveAdvanced();
  }

  Widget advancedSettings() => Column(
    children: [
      Card(
        child: SwitchListTile(
          title: const Text('Dark mode'),
          subtitle: const Text(
            'Use a darker color scheme throughout Pantry Logic.',
          ),
          value: prefs.darkMode,
          onChanged: (value) => updateFeatures(() {
            prefs.darkMode = value;
            appThemeMode.value = value ? ThemeMode.dark : ThemeMode.light;
          }),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: FilledButton.icon(
          onPressed: busy ? null : () => run(persistSettings),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save settings'),
        ),
      ),
      Card(
        child: ExpansionTile(
          initiallyExpanded: false,
          title: const Text('Planning & cooldowns'),
          children: [
            ListTile(
              title: Text('Default menu length: ${prefs.days} days'),
              subtitle: Slider(
                value: prefs.days.toDouble(),
                min: 1,
                max: 14,
                divisions: 13,
                label: '${prefs.days}',
                onChanged: (v) => updateFeatures(() => prefs.days = v.round()),
              ),
            ),
            for (final side in [false, true])
              ListTile(
                title: Text(
                  '${side ? 'Side dishes' : 'Main dishes'}: ${side ? prefs.sideCooldown : prefs.cooldown} days before repeating',
                ),
                subtitle: Slider(
                  value: (side ? prefs.sideCooldown : prefs.cooldown)
                      .clamp(0, 90)
                      .toDouble(),
                  min: 0,
                  max: 90,
                  divisions: 90,
                  onChanged: (v) => updateFeatures(() {
                    if (side) {
                      prefs.sideCooldown = v.round();
                    } else {
                      prefs.cooldown = v.round();
                    }
                  }),
                ),
              ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Leave a recipe’s cooldown blank to use these defaults. You can explicitly override a cooldown when choosing a replacement.',
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Weekly protein allowances • Monday–Sunday. These are maximum dinners across all saved menus and cooking history. No protein is tied to a weekday. Choose unlimited for flexible choices.',
              ),
            ),
            for (final protein in proteins)
              Padding(
                padding: const EdgeInsets.all(8),
                child: DropdownButtonFormField<int>(
                  isExpanded: true,
                  initialValue: prefs.weeklyLimits[protein] ?? -1,
                  decoration: InputDecoration(
                    labelText: '$protein per calendar week',
                  ),
                  items: [
                    const DropdownMenuItem(value: -1, child: Text('Unlimited')),
                    for (var n = 0; n <= 7; n++)
                      DropdownMenuItem(
                        value: n,
                        child: Text(n == 0 ? 'None' : 'Up to $n'),
                      ),
                  ],
                  onChanged: (v) => updateFeatures(
                    () => prefs.weeklyLimits[protein] = v == -1 ? null : v,
                  ),
                ),
              ),
          ],
        ),
      ),
      Card(
        child: ExpansionTile(
          title: const Text('Family profiles'),
          children: [
            ...prefs.family.map(
              (m) => ListTile(
                title: Text(m.name),
                subtitle: Text('Likes: ${m.likes}\nDislikes: ${m.dislikes}'),
                onTap: () => editMember(m),
                trailing: IconButton(
                  tooltip: 'Remove profile',
                  icon: const Icon(Icons.person_remove_outlined),
                  onPressed: () => run(() async {
                    updateFeatures(() => prefs.family.remove(m));
                    await saveAdvanced();
                  }),
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => editMember(),
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Add family member'),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Choose participants and guests when building a menu. Comma-separated dislikes filter matching ingredient names; always review the recipe yourself.',
              ),
            ),
          ],
        ),
      ),
      Card(
        child: ExpansionTile(
          title: const Text('Kitchen, region & shopping'),
          children: [
            for (final item in [
              ('Cooking equipment', prefs.equipment),
              ('Region / country', prefs.region),
              ('Frequent stores', prefs.stores),
            ])
              ListTile(
                title: Text(item.$1),
                subtitle: Text(item.$2.isEmpty ? 'Tap to set' : item.$2),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () async {
                  final v = await askText(item.$1, item.$2);
                  if (v != null) {
                    updateFeatures(() {
                      if (item.$1 == 'Cooking equipment') {
                        prefs.equipment = v;
                      } else if (item.$1 == 'Region / country') {
                        prefs.region = v;
                      } else {
                        prefs.stores = v;
                      }
                    });
                  }
                },
              ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Move categories into the order you walk through your store. Region, stores and equipment guide AI recipes.',
              ),
            ),
            for (final e in prefs.aisleOrder.indexed)
              ListTile(
                dense: true,
                title: Text(e.$2),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Move up',
                      onPressed: e.$1 == 0
                          ? null
                          : () => updateFeatures(() {
                              prefs.aisleOrder.removeAt(e.$1);
                              prefs.aisleOrder.insert(e.$1 - 1, e.$2);
                            }),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      tooltip: 'Move down',
                      onPressed: e.$1 == prefs.aisleOrder.length - 1
                          ? null
                          : () => updateFeatures(() {
                              prefs.aisleOrder.removeAt(e.$1);
                              prefs.aisleOrder.insert(e.$1 + 1, e.$2);
                            }),
                      icon: const Icon(Icons.arrow_downward),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      Card(
        child: ExpansionTile(
          title: const Text('Measurement style'),
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: prefs.measurementSystem,
                decoration: const InputDecoration(
                  labelText: 'Measurement system',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'metric',
                    child: Text('Metric standard'),
                  ),
                  DropdownMenuItem(value: 'us', child: Text('US customary')),
                  DropdownMenuItem(value: 'uk', child: Text('UK / imperial')),
                ],
                onChanged: (v) =>
                    updateFeatures(() => prefs.measurementSystem = v!),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: prefs.volumeStyle,
                decoration: const InputDecoration(labelText: 'Volume style'),
                items: const [
                  DropdownMenuItem(value: 'ml', child: Text('mL / litres')),
                  DropdownMenuItem(
                    value: 'kitchen',
                    child: Text(
                      'Smart cups & spoons',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                onChanged: (v) => updateFeatures(() => prefs.volumeStyle = v!),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Example: ${Measurements.format(
                  Ingredient(name: 'flour', quantity: 1, unit: 'US cup'),
                  system: prefs.measurementSystem,
                  volumeStyle: prefs.volumeStyle,
                )} flour. Smart units keep cup-sized amounts in cups and small amounts in spoons. Metric cups are 250 mL; US cups 236.59 mL; traditional imperial cups 284.13 mL. UK imperial spoons use the traditional imperial sizes. Unqualified source cups stay unchanged until their size is specified. Mass and volume are never interchanged using an assumed density.',
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget aiSettings() => Column(
    children: [
      FilledButton.icon(
        onPressed: busy ? null : () => run(persistSettings),
        icon: const Icon(Icons.save_outlined),
        label: const Text('Save AI settings'),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: TextField(
          controller: profileField,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Default AI recipe preferences',
            hintText: 'Quick meals, less washing up…',
          ),
        ),
      ),
      Card(
        child: ExpansionTile(
          title: const Text('AI Configuration'),
          initiallyExpanded: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: prefs.provider,
                decoration: const InputDecoration(
                  labelText: 'Preferred provider',
                ),
                items: providerModels.keys
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (p) => updateFeatures(() => prefs.provider = p!),
              ),
            ),
            SwitchListTile(
              title: const Text('Try other configured providers on failure'),
              subtitle: const Text(
                'Sends the same recipe text/image and relevant preferences to backups. Each provider may charge separately.',
              ),
              value: prefs.fallback,
              onChanged: (v) => updateFeatures(() => prefs.fallback = v),
            ),
            for (final p in providerModels.keys)
              ExpansionTile(
                title: Text(p),
                children: [
                  ...[
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        controller: keyFor(p),
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(labelText: '$p API key'),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        controller: modelFor(p),
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'Model ID (editable)',
                          helperText:
                              'Any model available to your API key. You can paste models/… for Gemini.',
                        ),
                      ),
                    ),
                  ],
                  TextButton(
                    onPressed: busy ? null : () => loadModels(p),
                    child: const Text('Load available models'),
                  ),
                  if (aiStatus[p] != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(aiStatus[p]!),
                    ),
                  TextButton(
                    onPressed: () => openLink(providerLinks[p]!),
                    child: Text('Get a $p API key'),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text(
                      'Sign in at the provider’s developer console, create a project/API key, enable billing if required, then paste the key here and Save settings. A chat subscription is separate from API access. Keys stay in secure storage and are excluded from backups.',
                    ),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : () => testProvider(p),
                    icon: const Icon(Icons.network_check),
                    label: const Text('Test connection (small API request)'),
                  ),
                ],
              ),
          ],
        ),
      ),
    ],
  );
  Future<void> testProvider(String p) async {
    await run(() async {
      updateFeatures(() => aiStatus[p] = 'Testing ${modelFor(p).text.trim()}…');
      try {
        await serviceFor(p).parseRecipe(
          'One serving of boiled rice: 100 g rice and 200 ml water. Bring to boil and simmer covered for 15 minutes.',
        );
        updateFeatures(
          () => aiStatus[p] =
              '$p connection and structured recipe response verified for ${modelFor(p).text.trim()}.',
        );
      } catch (e) {
        updateFeatures(
          () => aiStatus[p] = AiExceptionHandler.describe(e).message,
        );
      }
    });
  }

  Future<void> loadModels(String p) async {
    List<String>? choices;
    await run(() async {
      try {
        choices = await serviceFor(p).availableModels();
      } catch (e) {
        updateFeatures(
          () => aiStatus[p] = AiExceptionHandler.describe(e).message,
        );
      }
    });
    if (choices == null || !mounted) return;
    final filter = TextEditingController();
    final chosen = await showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: Text('$p models available to your key'),
          content: SizedBox(
            width: 450,
            height: 400,
            child: Column(
              children: [
                TextField(
                  controller: filter,
                  decoration: const InputDecoration(
                    labelText: 'Filter model names',
                  ),
                  onChanged: (_) => update(() {}),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final name in choices!.where(
                        (s) =>
                            s.toLowerCase().contains(filter.text.toLowerCase()),
                      ))
                        ListTile(
                          title: Text(name),
                          onTap: () => Navigator.pop(c, name),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    if (chosen != null) updateFeatures(() => modelFor(p).text = chosen);
    Future<void>.delayed(const Duration(seconds: 1), filter.dispose);
  }

  Future<void> generateFlexible({bool allowAI = false}) async {
    final ids = Set<String>.from(
      selectedPeople.where((id) => prefs.family.any((m) => m.id == id)),
    );
    var count = prefs.days, guestCount = guests, fallbackServings = servings;
    final blurb = TextEditingController(text: planningBlurb);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => AlertDialog(
          title: const Text('Build your menu'),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('How many days? $count'),
                  Slider(
                    value: count.toDouble(),
                    min: 1,
                    max: 14,
                    divisions: 13,
                    onChanged: (v) => update(() => count = v.round()),
                  ),
                  ...prefs.family.map(
                    (m) => CheckboxListTile(
                      title: Text(m.name),
                      value: ids.contains(m.id),
                      onChanged: (v) => update(() {
                        if (v == true) {
                          ids.add(m.id);
                        } else {
                          ids.remove(m.id);
                        }
                      }),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(child: Text('Guests: $guestCount')),
                      IconButton(
                        onPressed: guestCount > 0
                            ? () => update(() => guestCount--)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      IconButton(
                        onPressed: guestCount < 20
                            ? () => update(() => guestCount++)
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  if (ids.isEmpty)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'People (without profiles): $fallbackServings',
                          ),
                        ),
                        IconButton(
                          onPressed: fallbackServings > 1
                              ? () => update(() => fallbackServings--)
                              : null,
                          icon: const Icon(Icons.remove),
                        ),
                        IconButton(
                          onPressed: fallbackServings < 20
                              ? () => update(() => fallbackServings++)
                              : null,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                  if (allowAI)
                    TextField(
                      controller: blurb,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Anything else for this menu?',
                        hintText: 'Quick dinners, use up spinach, try Italian…',
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Choose dates'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) {
      blurb.dispose();
      return;
    }
    selectedPeople = ids.toList();
    guests = guestCount;
    planningBlurb = blurb.text;
    blurb.dispose();
    final now = DateTime.now();
    final start = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'First dinner',
    );
    if (start == null || !mounted) return;
    if (plans.any((p) => p.start == day(start))) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Replace this menu?'),
          content: const Text(
            'Its dinners, sides and shopping checklist will be replaced. Cooking history stays.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Replace'),
            ),
          ],
        ),
      );
      if (yes != true) return;
    }
    await run(() async {
      final end = day(start).add(Duration(days: count));
      if (plans.any(
        (p) =>
            p.start != day(start) &&
            p.start.isBefore(end) &&
            p.start.add(Duration(days: p.meals.length)).isAfter(day(start)),
      )) {
        throw const FormatException(
          'These dates overlap an existing menu. Choose another start date.',
        );
      }
      final options = Preferences.decode(prefs.encode())..days = count;
      final candidates = [...recipes];
      List<Recipe>? meals;
      try {
        meals = FlexiblePlanner.plan(
          candidates,
          history,
          plans,
          start,
          options,
          selectedPeople,
        );
      } on FormatException {
        if (!allowAI) rethrow;
      }
      for (var i = 0; meals == null && i < count; i++) {
        final date = start.add(Duration(days: i));
        final counts = FlexiblePlanner.weeklyCounts(
          candidates,
          history,
          plans,
          date,
          replacing: day(start),
        );
        final allowed = proteins
            .where(
              (p) =>
                  options.weeklyLimits[p] == null ||
                  (counts[p] ?? 0) < options.weeklyLimits[p]!,
            )
            .toList();
        if (allowed.isEmpty) {
          throw const FormatException(
            'Every protein allowance for this calendar week is used. Adjust limits before generating more recipes.',
          );
        }
        allowed.sort(
          (a, b) => candidates
              .where(
                (r) =>
                    !r.isSide &&
                    r.protein == a &&
                    FlexiblePlanner.available(
                      r,
                      date,
                      options,
                      history,
                      plans,
                      replacing: day(start),
                    ),
              )
              .length
              .compareTo(
                candidates
                    .where(
                      (r) =>
                          !r.isSide &&
                          r.protein == b &&
                          FlexiblePlanner.available(
                            r,
                            date,
                            options,
                            history,
                            plans,
                            replacing: day(start),
                          ),
                    )
                    .length,
              ),
        );
        final slot = allowed.first;
        final draft = await ai.compose(
          protein: slot,
          excludedTitles: candidates.map((r) => r.title).toList(),
          freshIngredients: candidates
              .skip(recipes.length)
              .expand((r) => r.ingredients)
              .where((i) => i.isPerishable)
              .map((i) => i.name)
              .toList(),
          profile:
              '${profileField.text}. ${prefs.context(selectedPeople)}. $planningBlurb.',
        );
        candidates.add(draft.withId(-i - 1));
        try {
          meals = FlexiblePlanner.plan(
            candidates,
            history,
            plans,
            start,
            options,
            selectedPeople,
          );
        } on FormatException {
          /* Try the next missing slot. */
        }
      }
      if (meals == null) {
        throw const FormatException(
          'AI could not fill this menu. Try fewer days or adjust weekly protein limits and dislikes.',
        );
      }
      await db!.transaction(() async {
        final saved = <Recipe>[];
        for (final r in meals!) {
          saved.add(
            r.id != null && r.id! < 0
                ? await db!.saveRecipe(
                    Recipe.fromJson({...r.toJson(), 'id': null}),
                  )
                : r,
          );
        }
        final sides = <int, Recipe>{};
        for (var i = 0; i < saved.length; i++) {
          final date = day(start).add(Duration(days: i));
          final fresh = saved[i].ingredients
              .where((v) => v.isPerishable)
              .map((v) => normalized(v.name))
              .toSet();
          final candidates = recipes
              .where(
                (r) =>
                    r.isSide &&
                    prefs.accepts(r, selectedPeople) &&
                    FlexiblePlanner.available(
                      r,
                      date,
                      prefs,
                      history,
                      plans,
                      replacing: day(start),
                    ) &&
                    !sides.entries.any(
                      (e) =>
                          e.value.id == r.id &&
                          i - e.key < prefs.effectiveCooldown(r),
                    ),
              )
              .toList();
          candidates.sort(
            (a, b) => b.ingredients
                .where((v) => fresh.contains(normalized(v.name)))
                .length
                .compareTo(
                  a.ingredients
                      .where((v) => fresh.contains(normalized(v.name)))
                      .length,
                ),
          );
          if (candidates.isNotEmpty) sides[i] = candidates.first;
        }
        await db!.savePlan(
          MealPlan(
            start: day(start),
            meals: saved,
            servings:
                (ids.isEmpty ? fallbackServings : ids.length) + guestCount,
            people: selectedPeople,
            guests: guestCount,
            sides: sides,
          ),
        );
      });
      await reload(select: day(start));
    });
  }

  Future<void> mealAction(int index, String action) async {
    final plan = active!;
    if (action == 'viewSide') {
      await details(plan.sides[index]!);
      return;
    }
    if (action == 'removeSide') {
      await run(() async {
        plan.sides.remove(index);
        plan.checked.clear();
        await db!.savePlan(plan);
        await reload();
      });
      return;
    }
    final side = action == 'side';
    if (action == 'regenerate') {
      await generateReplacement(plan, index, false);
      return;
    }
    final date = plan.start.add(Duration(days: index));
    final choices = recipes.where((r) => r.isSide == side).toList();
    choices.sort((a, b) {
      final fresh = plan.meals[index].ingredients
          .map((i) => normalized(i.name))
          .toSet();
      int score(Recipe r) =>
          (prefs.accepts(r, plan.people) ? 100 : 0) +
          r.ingredients.where((i) => fresh.contains(normalized(i.name))).length;
      return score(b).compareTo(score(a));
    });
    final selected = await showDialog<Recipe>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(side ? 'Choose a side dish' : 'Replace dinner'),
        content: SizedBox(
          width: 450,
          height: 350,
          child: ListView(
            children: [
              if (side)
                TextButton(
                  onPressed: () {
                    Navigator.pop(c);
                    generateReplacement(plan, index, true);
                  },
                  child: const Text('Let AI recommend a new side'),
                ),
              if (choices.isEmpty)
                const Text('No matching recipes yet. Add one in Recipes.'),
              ...choices.map((r) {
                final available = FlexiblePlanner.available(
                  r,
                  date,
                  prefs,
                  history,
                  plans,
                  replacing: plan.start,
                );
                return ListTile(
                  title: Text(r.title),
                  subtitle: Text(
                    '${available ? 'Available' : 'On cooldown — override required'}${prefs.accepts(r, plan.people) ? '' : ' • Contains a disliked ingredient'}',
                  ),
                  onTap: () => Navigator.pop(c, r),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selected != null) await assignMeal(plan, index, selected, side);
  }

  Future<void> generateReplacement(MealPlan plan, int index, bool side) async {
    Recipe? draft;
    final note = await askText(
      side ? 'Side dish preferences' : 'What should be different?',
      '',
    );
    if (note == null) return;
    await run(() async {
      draft = await ai.compose(
        protein: side ? 'vegetarian' : plan.meals[index].protein,
        excludedTitles: recipes.map((r) => r.title).toList(),
        freshIngredients: plan.meals[index].ingredients
            .where((i) => i.isPerishable)
            .map((i) => i.name)
            .toList(),
        profile:
            '${profileField.text}. ${prefs.context(plan.people)}. $note. ${side ? 'Create a side dish to complement ${plan.meals[index].title}.' : 'Replace ${plan.meals[index].title} with a substantially different dish.'}',
      );
    });
    if (draft == null || !mounted) return;
    final reviewed = await Navigator.of(context).push<Recipe>(
      MaterialPageRoute(
        builder: (_) => RecipeEditor(
          recipe: Recipe.fromJson({...draft!.toJson(), 'is_side': side}),
        ),
      ),
    );
    if (reviewed == null) return;
    Recipe? saved;
    await run(() async {
      saved = await db!.saveRecipe(reviewed);
      await reload();
    });
    if (saved != null) await assignMeal(plan, index, saved!, side);
  }

  Future<void> assignMeal(
    MealPlan plan,
    int index,
    Recipe recipe,
    bool side,
  ) async {
    final date = plan.start.add(Duration(days: index));
    if (!side) {
      final counts = FlexiblePlanner.weeklyCounts(
        recipes,
        history,
        plans,
        date,
        excludingDate: day(date),
      );
      final limit = prefs.weeklyLimits[recipe.protein];
      if (limit != null && (counts[recipe.protein] ?? 0) >= limit) {
        if (!mounted) return;
        final override = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Weekly protein allowance reached'),
            content: Text(
              'This week already has ${counts[recipe.protein] ?? 0} ${recipe.protein} dinner${(counts[recipe.protein] ?? 0) == 1 ? '' : 's'} (limit $limit). Keep this replacement anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Use anyway'),
              ),
            ],
          ),
        );
        if (override != true) return;
      }
    }

    final duplicate =
        [
          ...plan.meals.indexed
              .where((e) => side || e.$1 != index)
              .map((e) => (e.$1, e.$2)),
          ...plan.sides.entries
              .where((e) => !side || e.key != index)
              .map((e) => (e.key, e.value)),
        ].any(
          (e) =>
              normalized(e.$2.title) == normalized(recipe.title) &&
              (e.$1 - index).abs() < prefs.effectiveCooldown(recipe),
        );
    final blocked =
        duplicate ||
        !FlexiblePlanner.available(
          recipe,
          date,
          prefs,
          history,
          plans,
          replacing: plan.start,
        );
    if (blocked || !prefs.accepts(recipe, plan.people)) {
      if (!mounted) return;
      final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Use this recipe anyway?'),
          content: Text(
            '${blocked ? '${recipe.title} is within its ${prefs.effectiveCooldown(recipe)}-day cooldown. This overrides it only for this meal.\n' : ''}${prefs.accepts(recipe, plan.people) ? '' : 'This recipe matches a participant’s dislikes.'}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Use anyway'),
            ),
          ],
        ),
      );
      if (yes != true) return;
    }
    await run(() async {
      if (side) {
        plan.sides[index] = recipe;
      } else {
        plan.meals[index] = recipe;
      }
      if (blocked) {
        plan.cooldownOverrides.add(index);
      } else {
        plan.cooldownOverrides.remove(index);
      }
      plan.checked.clear();
      await db!.savePlan(plan);
      await reload(select: plan.start);
    });
  }

  Widget shoppingDatePicker() => Card(
    child: ExpansionTile(
      initiallyExpanded: true,
      title: const Text('Shopping for these days'),
      subtitle: Text(
        '${active!.shoppingDays.length} selected · ${prefs.stores}',
      ),
      children: [
        Wrap(
          spacing: 6,
          children: [
            for (final e in active!.meals.indexed)
              FilterChip(
                label: Text(dateLabel(active!.start.add(Duration(days: e.$1)))),
                selected: active!.shoppingDays.contains(e.$1),
                onSelected: busy
                    ? null
                    : (v) => run(() async {
                        final p = active!;
                        if (v) {
                          p.shoppingDays.add(e.$1);
                        } else {
                          p.shoppingDays.remove(e.$1);
                        }
                        p.checked.clear();
                        await db!.savePlan(p);
                        await reload();
                      }),
              ),
          ],
        ),
      ],
    ),
  );
  String displayAmount(Ingredient i) => Measurements.format(
    i,
    system: prefs.measurementSystem,
    volumeStyle: prefs.volumeStyle,
  );

  Future<void> alexaExport(List<Ingredient> items) async {
    final text = items
        .where((i) => !active!.checked.contains(GroceryAggregator.key(i)))
        .map((i) => '${i.name}: ${displayAmount(i)}')
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Shopping list copied'),
        content: const Text(
          'Amazon retired third-party Alexa list access in July 2024. Pantry Logic cannot directly sync to Alexa.\n\nOpen the Alexa app → More → Lists & Notes → Shopping, then add the copied items individually, or say “Alexa, add … to my shopping list.”\n\nYou can also share this text to another app.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(c);
              openLink('https://www.amazon.com/alexa');
            },
            child: const Text('Alexa help'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(c);
              try {
                await const MethodChannel(
                  'pantry_logic/actions',
                ).invokeMethod('share', text);
              } catch (_) {
                message('List is on your clipboard.');
              }
            },
            child: const Text('Share text'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
