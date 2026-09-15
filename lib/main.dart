import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'database.dart';
import 'models.dart';
import 'planning_engine.dart';
import 'grocery_aggregator.dart';
import 'ai_service.dart';
import 'seed.dart';
import 'preferences.dart';
import 'providers.dart';
import 'measurements.dart';
import 'core/errors/ai_exception_handler.dart';
import 'features/recipes/services/recipe_ingestion_service.dart';
import 'side_seeds.dart';
part 'features.dart';
part 'features/recipes/presentation/recipe_ingest_view.dart';

const ink = Color(0xFF243A30);
const cream = Color(0xFFF7F6EF);
const accent = Color(0xFFDBE8B7);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PantryLogicApp());
}

class PantryLogicApp extends StatelessWidget {
  const PantryLogicApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Pantry Logic',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: ink, surface: cream),
      scaffoldBackgroundColor: cream,
      appBarTheme: const AppBarTheme(
        backgroundColor: cream,
        foregroundColor: ink,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: Colors.white,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    ),
    home: const Home(),
  );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  void updateFeatures(VoidCallback action) {
    if (mounted) setState(action);
  }

  Preferences prefs = Preferences();
  String settingsSection = 'general';
  String ingestMode = 'url';
  bool showCaption = false;
  final urlField = TextEditingController();
  final captionFocus = FocusNode();
  final captionAnchor = GlobalKey();
  AiFailure? ingestFailure;
  final aiStatus = <String, String>{};
  final providerKeys = <String, TextEditingController>{};
  final providerModelFields = <String, TextEditingController>{};
  List<String> selectedPeople = [];
  int guests = 0;
  String planningBlurb = '';

  AppDatabase? db;
  List<Recipe> recipes = [];
  List<CookedMeal> history = [];
  List<MealPlan> plans = [];
  MealPlan? active;
  int tab = 0, servings = 2;
  bool busy = false, ready = false;
  String? startupError;
  String search = '', proteinFilter = 'all';
  final raw = TextEditingController(),
      keyField = TextEditingController(),
      modelField = TextEditingController(text: 'gemini-flash-latest'),
      profileField = TextEditingController();
  final secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  Uint8List? imageBytes;
  String? imageName, imageMime;
  StreamSubscription<List<SharedMediaFile>>? shares;
  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    try {
      db = await AppDatabase.open();
      if (await db!.setting('initialized') != 'true') {
        await db!.transaction(() async {
          for (final r in seedRecipes()) {
            await db!.saveRecipe(r);
          }
          await db!.setSetting('initialized', 'true');
        });
      }
      servings = int.tryParse(await db!.setting('servings') ?? '') ?? 2;
      if (await db!.setting('side_seeds') != 'true') {
        final existing = (await db!.recipes())
            .map((r) => normalized(r.title))
            .toSet();
        await db!.transaction(() async {
          for (final r in starterSides()) {
            if (!existing.contains(normalized(r.title))) {
              await db!.saveRecipe(r);
            }
          }
          await db!.setSetting('side_seeds', 'true');
        });
      }
      modelField.text = await db!.setting('model') ?? 'gemini-flash-latest';
      profileField.text = await db!.setting('profile') ?? '';
      prefs = Preferences.decode(await db!.setting('preferences'));
      try {
        keyField.text = await secure.read(key: 'gemini_key') ?? '';
      } catch (_) {
        /* Offline features remain available if keychain unavailable. */
      }
      for (final p in providerModels.keys.where((p) => p != 'Gemini')) {
        String key = '';
        try {
          key = await secure.read(key: '${p.toLowerCase()}_key') ?? '';
        } catch (_) {
          message('Could not read $p key. Re-enter it in Settings.');
        }
        providerKeys[p] = TextEditingController(text: key);
        providerModelFields[p] = TextEditingController(
          text: await db!.setting('${p}_model') ?? providerModels[p],
        );
      }
      await reload();
      if (mounted) setState(() => ready = true);
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => birthdayPrompt());
      }
      if (Platform.isAndroid) {
        shares = ReceiveSharingIntent.instance.getMediaStream().listen(
          handleShares,
          onError: (Object e) => message(
            'Could not read shared content. Try importing it directly.',
          ),
        );
        handleShares(await ReceiveSharingIntent.instance.getInitialMedia());
        ReceiveSharingIntent.instance.reset();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => startupError =
              'Could not open local storage. Please close and reopen Pantry Logic.',
        );
      }
    }
  }

  Future<void> handleShares(List<SharedMediaFile> files) async {
    if (files.isEmpty || !mounted) return;
    final file = files.first;
    if (file.type == SharedMediaType.image) {
      try {
        final bytes = await File(file.path).readAsBytes();
        if (bytes.length > 10 * 1024 * 1024) {
          throw const FormatException('Image exceeds 10 MB.');
        }
        imageBytes = bytes;
        imageName = 'Shared screenshot';
        ingestMode = 'image';
        imageMime = file.mimeType ?? 'image/jpeg';
      } catch (_) {
        message('Could not read that image. Select it from Import.');
      }
    } else {
      final shared = Uri.tryParse(file.path.trim());
      if (shared != null &&
          shared.scheme == 'https' &&
          !file.path.contains(RegExp(r'\s'))) {
        urlField.text = file.path;
        raw.clear();
        ingestMode = 'url';
        showCaption = false;
      } else {
        raw.text = file.path;
        urlField.clear();
        ingestMode = 'text';
        showCaption = true;
      }
      ingestFailure = null;
      imageBytes = null;
      imageName = null;
    }
    if (mounted) setState(() => tab = 3);
  }

  Future<void> reload({DateTime? select}) async {
    final r = await db!.recipes(),
        h = await db!.history(),
        p = await db!.plans();
    final desired = select ?? active?.start;
    if (!mounted) return;
    setState(() {
      recipes = r;
      history = h;
      plans = p;
      active = p.where((p) => p.start == desired).firstOrNull ?? p.firstOrNull;
    });
  }

  @override
  void dispose() {
    shares?.cancel();
    db?.close();
    raw.dispose();
    urlField.dispose();
    captionFocus.dispose();
    keyField.dispose();
    modelField.dispose();
    profileField.dispose();
    for (final c in [...providerKeys.values, ...providerModelFields.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (e is AiRequestException || e is AiFallbackException) {
        showAiFailure(e);
        return;
      }
      message(
        e is FormatException
            ? e.message
            : e.toString().contains('UNIQUE')
            ? 'A recipe with this title already exists. Choose a different title.'
            : 'Something went wrong. Please try again.',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  AIService get ai => FallbackService([
    for (final p in [
      prefs.provider,
      if (prefs.fallback)
        ...providerModels.keys.where((p) => p != prefs.provider),
    ])
      if (keyFor(p).text.trim().isNotEmpty) serviceFor(p),
  ]);
  Future<void> edit([Recipe? recipe]) async {
    final result = await Navigator.of(context).push<Recipe>(
      MaterialPageRoute(
        builder: (_) => RecipeEditor(
          recipe: recipe,
          onSave: (value) async {
            await db!.saveRecipe(value);
            await reload();
          },
        ),
      ),
    );
    if (result != null) message('Recipe saved to your library.');
  }

  Future<void> generate({bool allowAI = false}) =>
      generateFlexible(allowAI: allowAI);

  Future<void> importRecipe() async {
    if (busy) return;
    setState(() {
      busy = true;
      ingestFailure = null;
    });
    Recipe? draft;
    try {
      draft = await RecipeIngestionService(ai).ingest(
        url: urlField.text,
        blurb: raw.text,
        image: imageBytes,
        mimeType: imageMime,
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => ingestFailure = AiExceptionHandler.describe(
            e,
            fromLink: urlField.text.trim().isNotEmpty,
          ),
        );
        showAiFailure(e, fromLink: urlField.text.trim().isNotEmpty);
        if (ingestFailure!.action == AiErrorAction.pasteText) focusCaption();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (draft != null && mounted) await edit(draft);
  }

  Future<void> pickImage() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
      if (picked == null) return;
      if (!mounted) return;
      final f = picked.files.single;
      if (f.size > 10 * 1024 * 1024) {
        message('Choose an image smaller than 10 MB.');
        return;
      }
      if (f.bytes == null || f.bytes!.isEmpty) {
        message(
          'This image could not be read. Please choose another screenshot.',
        );
        return;
      }
      setState(() {
        imageBytes = f.bytes;
        imageName = f.name;
        imageMime = f.extension?.toLowerCase() == 'png'
            ? 'image/png'
            : f.extension?.toLowerCase() == 'webp'
            ? 'image/webp'
            : 'image/jpeg';
      });
    } catch (_) {
      message(
        'The image picker could not open. Please try again or paste the recipe text.',
      );
    }
  }

  Future<void> compose() async {
    String protein = 'chicken';
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Compose a new dinner'),
          content: DropdownButtonFormField<String>(
            initialValue: protein,
            items: proteins
                .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                .toList(),
            onChanged: (v) => update(() => protein = v!),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, protein),
              child: const Text('Compose'),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    Recipe? draft;
    await run(() async {
      draft = await ai.compose(
        protein: chosen,
        excludedTitles: recipes.map((r) => r.title).toList(),
        freshIngredients:
            active?.meals
                .expand((r) => r.ingredients)
                .where((i) => i.isPerishable)
                .map((i) => i.name)
                .toSet()
                .toList() ??
            [],
        profile:
            '${profileField.text}. ${prefs.context(prefs.family.map((m) => m.id).toList())}',
      );
    });
    if (draft != null && mounted) await edit(draft);
  }

  Future<void> details(Recipe recipe) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .8,
        minChildSize: .4,
        maxChildSize: .95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
          children: [
            Text(
              recipe.title,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 10),
            Text(
              '${recipe.isSide ? 'Side dish' : recipe.protein} • ${recipe.servings} servings • ${prefs.effectiveCooldown(recipe)}-day cooldown${recipe.useDefaultCooldown ? ' (default)' : ''}${recipe.targetFrequencyDays == null ? '' : ' • repeats every ${recipe.targetFrequencyDays} days'}',
            ),
            const SizedBox(height: 24),
            const Text(
              'INGREDIENTS',
              style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.5),
            ),
            ...recipe.ingredients.map(
              (i) => ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(i.name),
                trailing: Text(displayAmount(i)),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'METHOD',
              style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.5),
            ),
            ...recipe.instructions.indexed.map(
              (s) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 15,
                  backgroundColor: accent,
                  child: Text('${s.$1 + 1}'),
                ),
                title: Text(s.$2),
              ),
            ),
            if (recipe.prepMinutes != null || recipe.cookMinutes != null)
              Text(
                'Prep: ${recipe.prepMinutes?.toString() ?? "—"} min • Cook: ${recipe.cookMinutes?.toString() ?? "—"} min',
              ),
            for (final note in recipe.reviewNotes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(note),
              ),
            if (recipe.sourceUrl != null)
              SelectableText('Source: ${recipe.sourceUrl}'),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                      helpText: 'When did you cook this?',
                    );
                    if (date == null) return;
                    await run(() async {
                      if (!recipes.any((r) => r.id == recipe.id)) {
                        throw const FormatException(
                          'This recipe was removed from the library. Restore it before logging a meal.',
                        );
                      }
                      await db!.markCooked(recipe.id!, date);
                      await reload();
                      message('Added to cooking history.');
                    });
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Log cooked'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    edit(
                      recipes.where((r) => r.id == recipe.id).firstOrNull ??
                          Recipe.fromJson({...recipe.toJson(), 'id': null}),
                    );
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit recipe'),
                ),
                TextButton(
                  onPressed: () async {
                    final yes = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete recipe?'),
                        content: const Text(
                          'This also removes its cooking history. Saved plans keep their recipe snapshot.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                    if (yes == true) {
                      await run(() async {
                        await db!.deleteRecipe(recipe.id!);
                        await reload();
                      });
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  child: const Text('Delete'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (startupError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(startupError!),
          ),
        ),
      );
    }
    if (!ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final bodies = [week, library, groceries, importing, settings];
    return Scaffold(
      appBar: AppBar(
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.spa_outlined),
              SizedBox(width: 10),
              Text(
                'Pantry Logic',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
            ],
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Center(
              child: Text(
                'LOCAL FIRST',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 2,
                  color: ink.withValues(alpha: .65),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final content = Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: bodies[tab](),
                  ),
                );
                return constraints.maxWidth >= 850
                    ? Row(
                        children: [
                          NavigationRail(
                            selectedIndex: tab,
                            onDestinationSelected: (i) =>
                                setState(() => tab = i),
                            labelType: NavigationRailLabelType.all,
                            destinations: destinations
                                .map(
                                  (d) => NavigationRailDestination(
                                    icon: d.icon,
                                    label: Text(d.label),
                                  ),
                                )
                                .toList(),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(child: content),
                        ],
                      )
                    : content;
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 850
          ? NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: destinations,
            )
          : null,
    );
  }

  static const destinations = [
    NavigationDestination(
      icon: Icon(Icons.calendar_view_week_outlined),
      label: 'Week',
    ),
    NavigationDestination(
      icon: Icon(Icons.menu_book_outlined),
      label: 'Recipes',
    ),
    NavigationDestination(
      icon: Icon(Icons.shopping_basket_outlined),
      label: 'Shop',
    ),
    NavigationDestination(
      icon: Icon(Icons.add_circle_outline),
      label: 'Import',
    ),
    NavigationDestination(icon: Icon(Icons.tune), label: 'Settings'),
  ];
  Widget heading(String eyebrow, String title, String subtitle) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: ink,
            fontSize: 11,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 34,
            height: 1.1,
            fontWeight: FontWeight.w700,
            color: ink,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF677468), height: 1.5),
        ),
      ],
    ),
  );
  Widget page(List<Widget> children) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      ...children,
      if ([0, 2, 4].contains(tab)) supportLink(),
    ],
  );
  Widget week() => page([
    heading(
      'A LITTLE PLANNING. A BETTER DINNER.',
      'Your week, well fed.',
      'Your dates. Less repetition. A shopping list that adds up.',
    ),
    Card(
      color: ink,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Make room for good food.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${prefs.days} days · $servings people · weekly protein limits',
              style: const TextStyle(color: accent),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: ink,
              ),
              onPressed: busy ? null : generate,
              icon: const Icon(Icons.auto_awesome_outlined),
              label: const Text('Build a menu'),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: accent),
              onPressed: busy ? null : () => generate(allowAI: true),
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text('Let AI fill any gaps'),
            ),
          ],
        ),
      ),
    ),
    if (plans.isNotEmpty)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: DropdownButtonFormField<DateTime>(
          initialValue: active?.start,
          key: ValueKey(active?.start),
          decoration: const InputDecoration(labelText: 'Saved week'),
          items: plans
              .map(
                (p) => DropdownMenuItem(
                  value: p.start,
                  child: Text(
                    'Week of ${dateLabel(p.start)} · ${p.servings} people',
                  ),
                ),
              )
              .toList(),
          onChanged: (v) =>
              setState(() => active = plans.firstWhere((p) => p.start == v)),
        ),
      ),
    if (active == null)
      const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Your first week starts here. Twelve starter recipes are ready in your library.',
        ),
      ),
    if (active != null)
      ...active!.meals.indexed.map((entry) {
        final date = active!.start.add(Duration(days: entry.$1));
        final r = entry.$2;
        final cooked = history.any(
          (h) => h.recipeId == r.id && day(h.date) == date,
        );
        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 8,
            ),
            leading: Container(
              width: 48,
              height: 52,
              decoration: BoxDecoration(
                color: cream,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    [
                      'MON',
                      'TUE',
                      'WED',
                      'THU',
                      'FRI',
                      'SAT',
                      'SUN',
                    ][date.weekday - 1],
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text('${date.day}', style: const TextStyle(fontSize: 22)),
                ],
              ),
            ),
            title: Text(
              r.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${r.protein} · ${active!.servings} servings${cooked ? ' · cooked' : ''}${active!.sides[entry.$1] == null ? '' : ' • Side: ${active!.sides[entry.$1]!.title}'}${active!.cooldownOverrides.contains(entry.$1) ? ' • Override' : ''}',
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (v) => mealAction(entry.$1, v),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'swap',
                  child: Text('Choose replacement / override cooldown'),
                ),
                const PopupMenuItem(
                  value: 'regenerate',
                  child: Text('Veto & generate another'),
                ),
                const PopupMenuItem(
                  value: 'side',
                  child: Text('Recommend / choose a side'),
                ),
                if (active!.sides[entry.$1] != null)
                  const PopupMenuItem(
                    value: 'viewSide',
                    child: Text('View side dish'),
                  ),
                if (active!.sides[entry.$1] != null)
                  const PopupMenuItem(
                    value: 'removeSide',
                    child: Text('Remove side dish'),
                  ),
              ],
            ),
            onTap: () => details(r),
          ),
        );
      }),
    if (active != null)
      Card(
        color: const Color(0xFFEAF0DE),
        child: ExpansionTile(
          title: const Text(
            'Use the fresh stuff',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text('Ingredient sharing & leftover reminders'),
          children: PlanningEngine.perishableNotes(active!.meals)
              .map(
                (n) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.eco_outlined, size: 18),
                  title: Text(n),
                ),
              )
              .toList(),
        ),
      ),
  ]);
  Widget library() {
    final filtered = recipes
        .where(
          (r) =>
              normalized(r.title).contains(normalized(search)) &&
              (proteinFilter == 'all' || r.protein == proteinFilter),
        )
        .toList();
    return page([
      heading(
        'YOUR PERSONAL COOKBOOK',
        'Keep the good ones.',
        '${recipes.length} recipes, stored on this device.',
      ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: busy ? null : () => edit(),
            icon: const Icon(Icons.add),
            label: const Text('New recipe'),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : compose,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Compose with AI'),
          ),
        ],
      ),
      const SizedBox(height: 18),
      TextField(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.search),
          hintText: 'Find a recipe',
        ),
        onChanged: (v) => setState(() => search = v),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 6,
        children: ['all', ...proteins]
            .map(
              (p) => ChoiceChip(
                label: Text(p),
                selected: proteinFilter == p,
                onSelected: (_) => setState(() => proteinFilter = p),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 16),
      if (filtered.isEmpty)
        const Text('No matching recipes. Add a recipe or change your search.'),
      ...filtered.map(
        (r) => Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              backgroundColor: accent,
              child: Icon(
                r.protein == 'vegetarian'
                    ? Icons.eco_outlined
                    : Icons.restaurant,
                color: ink,
              ),
            ),
            title: Text(
              r.title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${r.protein} · ${r.ingredients.length} ingredients${r.targetFrequencyDays != null ? ' · recurring' : ''}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => details(r),
          ),
        ),
      ),
    ]);
  }

  Widget groceries() {
    final items = active == null
        ? <Ingredient>[]
        : GroceryAggregator.consolidate(
            active!.shoppingRecipes,
            active!.servings,
          );
    items.sort(
      (a, b) => prefs.aisleOrder
          .indexOf(a.aisle)
          .compareTo(prefs.aisleOrder.indexOf(b.aisle)),
    );
    final checked = items
        .where((i) => active!.checked.contains(GroceryAggregator.key(i)))
        .length;
    return page([
      heading(
        'ONE TRIP. EVERYTHING YOU NEED.',
        'The shopping list.',
        active == null
            ? 'Plan a week to build your list.'
            : 'Week of ${dateLabel(active!.start)} · $checked of ${items.length} picked up',
      ),
      if (active != null) shoppingDatePicker(),
      if (items.isNotEmpty) ...[
        TextButton.icon(
          onPressed: () => alexaExport(items),
          icon: const Icon(Icons.ios_share),
          label: const Text('Export for Alexa / share'),
        ),
        LinearProgressIndicator(
          value: checked / items.length,
          minHeight: 6,
          borderRadius: BorderRadius.circular(8),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () async {
              final text = items
                  .map(
                    (i) =>
                        '${active!.checked.contains(GroceryAggregator.key(i)) ? '[x]' : '[ ]'} ${i.name}: ${displayAmount(i)}',
                  )
                  .join('\n');
              await Clipboard.setData(ClipboardData(text: text));
              message('Shopping list copied.');
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy list'),
          ),
        ),
      ],
      for (final aisle in items.map((i) => i.aisle).toSet()) ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            aisle.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
            ),
          ),
        ),
        Card(
          child: Column(
            children: items.where((i) => i.aisle == aisle).map((i) {
              final key = GroceryAggregator.key(i);
              return CheckboxListTile(
                controlAffinity: ListTileControlAffinity.leading,
                value: active!.checked.contains(key),
                title: Text(
                  i.name,
                  style: TextStyle(
                    decoration: active!.checked.contains(key)
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                subtitle: i.isPerishable
                    ? const Text('Fresh · check your fridge first')
                    : null,
                secondary: Text(displayAmount(i)),
                onChanged: busy
                    ? null
                    : (value) => run(() async {
                        final plan = active!;
                        final previous = Set<String>.from(plan.checked);
                        setState(() {
                          if (value == true) {
                            plan.checked.add(key);
                          } else {
                            plan.checked.remove(key);
                          }
                        });
                        try {
                          await db!.savePlan(plan);
                        } catch (_) {
                          setState(() {
                            plan.checked
                              ..clear()
                              ..addAll(previous);
                          });
                          rethrow;
                        }
                      }),
              );
            }).toList(),
          ),
        ),
      ],
      if (active != null)
        const Padding(
          padding: EdgeInsets.only(top: 18),
          child: Text(
            'Units follow your settings. Weight and volume convert within their own dimension. Use recipe editing to specify a measured weight, volume or count equivalent.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
    ]);
  }

  Widget importing() => ingestView();
  Widget settings() => page([
    heading(
      'MAKE IT YOURS',
      'A calmer kitchen.',
      'Your recipes and plans stay on this device. Back them up before switching phones.',
    ),
    SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'general', label: Text('General')),
        ButtonSegment(value: 'ai', label: Text('AI')),
      ],
      selected: {settingsSection},
      onSelectionChanged: (v) => setState(() => settingsSection = v.single),
    ),
    const SizedBox(height: 16),
    if (settingsSection == 'ai')
      aiSettings()
    else ...[
      advancedSettings(),
      const SizedBox(height: 24),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () => run(() async {
                    final data = await db!.export();
                    final path = await FilePicker.platform.saveFile(
                      dialogTitle: 'Save Pantry Logic backup',
                      fileName:
                          'pantry_logic-backup-${dateLabel(DateTime.now())}.json',
                      type: FileType.custom,
                      allowedExtensions: ['json'],
                      bytes: Uint8List.fromList(utf8.encode(data)),
                    );
                    if (path != null) {
                      if (!Platform.isAndroid && !Platform.isIOS) {
                        await File(path).writeAsString(data);
                      }
                      message('Backup saved.');
                    }
                  }),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Export backup'),
          ),
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () => run(() async {
                    final f = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['json'],
                      withData: true,
                    );
                    if (f == null) return;
                    if (f.files.single.size > 10 * 1024 * 1024) {
                      throw const FormatException('Backup exceeds 10 MB.');
                    }
                    await db!.restore(utf8.decode(f.files.single.bytes!));
                    prefs = Preferences.decode(
                      await db!.setting('preferences'),
                    );
                    profileField.text =
                        await db!.setting('profile') ?? profileField.text;
                    servings =
                        int.tryParse(await db!.setting('servings') ?? '') ??
                        servings;
                    await reload();
                    message(
                      'Backup merged. Matching titles were kept; matching weeks were restored.',
                    );
                  }),
            icon: const Icon(Icons.upload_outlined),
            label: const Text('Restore backup'),
          ),
        ],
      ),
      const SizedBox(height: 24),
      Text(
        'Cooking history (${history.length})',
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
      ),
      if (history.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('Open a recipe and tap “Log cooked” after dinner.'),
        ),
      ...history
          .take(50)
          .map(
            (h) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                recipes.where((r) => r.id == h.recipeId).firstOrNull?.title ??
                    'Deleted recipe',
              ),
              subtitle: Text(dateLabel(h.date)),
              trailing: IconButton(
                tooltip: 'Undo cooking log',
                onPressed: busy
                    ? null
                    : () => run(() async {
                        await db!.undoCooked(h.id);
                        await reload();
                      }),
                icon: const Icon(Icons.undo),
              ),
            ),
          ),
    ],
  ]);
}

String quantity(double number) =>
    number.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

class RecipeEditor extends StatefulWidget {
  final Recipe? recipe;
  final Future<void> Function(Recipe)? onSave;
  const RecipeEditor({super.key, this.recipe, this.onSave});
  @override
  State<RecipeEditor> createState() => _RecipeEditorState();
}

class _RecipeEditorState extends State<RecipeEditor> {
  bool saving = false, isSide = false;
  late final TextEditingController title,
      servings,
      cooldown,
      frequency,
      prepTime,
      cookTime,
      notes,
      instructions;
  final ingredientRows = <IngredientFields>[];
  late String protein;
  String? error;
  @override
  void initState() {
    super.initState();
    final r = widget.recipe;
    title = TextEditingController(text: r?.title);
    prepTime = TextEditingController(text: r?.prepMinutes?.toString() ?? '');
    cookTime = TextEditingController(text: r?.cookMinutes?.toString() ?? '');
    notes = TextEditingController(text: r?.reviewNotes.join('\n') ?? '');
    servings = TextEditingController(text: '${r?.servings ?? 2}');
    cooldown = TextEditingController(
      text: r == null || r.useDefaultCooldown ? '' : '${r.cooldownDays}',
    );
    isSide = r?.isSide ?? false;
    frequency = TextEditingController(
      text: r?.targetFrequencyDays?.toString() ?? '',
    );
    protein = r?.protein ?? 'vegetarian';
    ingredientRows.addAll(
      r?.ingredients.map(IngredientFields.new) ?? [IngredientFields()],
    );
    instructions = TextEditingController(text: r?.instructions.join('\n'));
  }

  @override
  void dispose() {
    for (final c in [
      title,
      servings,
      cooldown,
      frequency,
      instructions,
      prepTime,
      cookTime,
      notes,
    ]) {
      c.dispose();
    }
    for (final row in ingredientRows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final parsed = ingredientRows.map((row) => row.value()).toList();
      final recipe = Recipe(
        id: widget.recipe?.id,
        title: title.text.trim(),
        protein: protein,
        servings: int.parse(servings.text),
        cooldownDays: cooldown.text.trim().isEmpty
            ? 18
            : int.parse(cooldown.text),
        useDefaultCooldown: cooldown.text.trim().isEmpty,
        isSide: isSide,
        targetFrequencyDays: frequency.text.trim().isEmpty
            ? null
            : int.parse(frequency.text),
        ingredients: parsed,
        instructions: instructions.text
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        sourceUrl: widget.recipe?.sourceUrl,
        reviewNotes: notes.text
            .split('\n')
            .where((n) => n.trim().isNotEmpty)
            .toList(),
        prepMinutes: prepTime.text.trim().isEmpty
            ? null
            : int.parse(prepTime.text),
        cookMinutes: cookTime.text.trim().isEmpty
            ? null
            : int.parse(cookTime.text),
      );
      await widget.onSave?.call(recipe);
      if (mounted) Navigator.pop(context, recipe);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException
              ? e.message
              : e.toString().contains('UNIQUE')
              ? 'A recipe with this title already exists. Choose a different title.'
              : 'Could not save. Check your recipe fields and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.recipe == null ? 'New recipe' : 'Review recipe'),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Make it a keeper.',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Check ingredient amounts, servings and cooking steps before saving.',
            ),
            for (final note in widget.recipe?.reviewNotes ?? <String>[])
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(note),
                ),
              ),
            const SizedBox(height: 24),
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Recipe title'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: protein,
              decoration: const InputDecoration(labelText: 'Protein'),
              items: proteins
                  .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                  .toList(),
              onChanged: (v) => setState(() => protein = v!),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: servings,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Servings'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: cooldown,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Cooldown days (optional)',
                      helperText: 'Blank = Settings default',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: prepTime,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Prep time (minutes)',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: cookTime,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Cook time (minutes)',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notes,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Notes / source clarifications',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: frequency,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Repeat every N days (optional)',
                helperText: 'Leave blank for non-recurring recipes.',
              ),
            ),
            SwitchListTile(
              title: const Text('Side dish'),
              value: isSide,
              onChanged: (v) => setState(() => isSide = v),
            ),
            const SizedBox(height: 24),
            const Text(
              'Ingredients',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...ingredientRows.map(
              (row) => Card(
                key: ObjectKey(row),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: row.name,
                              decoration: const InputDecoration(
                                labelText: 'Ingredient',
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove ingredient',
                            onPressed: () => setState(() {
                              ingredientRows.remove(row);
                              row.dispose();
                            }),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: row.amount,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Amount (blank = as needed)',
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: row.unit,
                              decoration: const InputDecoration(
                                labelText: 'Unit',
                                hintText: 'g, ml, whole',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: row.aisle,
                        decoration: const InputDecoration(
                          labelText: 'Shopping aisle',
                        ),
                        items: {...GroceryAggregator.aisles, row.aisle}
                            .map(
                              (a) => DropdownMenuItem(value: a, child: Text(a)),
                            )
                            .toList(),
                        onChanged: (v) => row.aisle = v!,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Use while fresh'),
                        subtitle: const Text(
                          'Herbs, greens or fresh aromatics',
                        ),
                        value: row.fresh,
                        onChanged: (v) => setState(() => row.fresh = v),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () =>
                    setState(() => ingredientRows.add(IngredientFields())),
                icon: const Icon(Icons.add),
                label: const Text('Add ingredient'),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: instructions,
              minLines: 5,
              maxLines: 16,
              decoration: const InputDecoration(
                labelText: 'Method — one step per line',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton.icon(
              onPressed: saving ? null : save,
              icon: const Icon(Icons.check),
              label: const Text('Save recipe'),
            ),
          ],
        ),
      ),
    ),
  );
}

class IngredientFields {
  final TextEditingController name, amount, unit;
  String aisle;
  bool fresh;
  IngredientFields([Ingredient? item])
    : name = TextEditingController(text: item?.name),
      amount = TextEditingController(
        text: item == null || !item.quantitySpecified
            ? ''
            : quantity(item.quantity),
      ),
      unit = TextEditingController(text: item?.unit ?? 'g'),
      aisle = item?.aisle ?? 'Produce',
      fresh = item?.isPerishable ?? false;
  Ingredient value() => Ingredient(
    name: name.text.trim(),
    quantity: double.tryParse(amount.text.replaceAll(',', '.')) ?? 0,
    quantitySpecified: amount.text.trim().isNotEmpty,
    unit: unit.text.trim(),
    aisle: aisle,
    isPerishable: fresh,
  );
  void dispose() {
    name.dispose();
    amount.dispose();
    unit.dispose();
  }
}
