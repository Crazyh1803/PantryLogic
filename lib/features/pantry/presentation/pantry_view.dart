part of '../../../main.dart';

extension _PantryView on _HomeState {
  Widget shop() => shopSection == 'pantry' ? pantry() : groceries();

  Widget shopSwitcher() => SegmentedButton<String>(
    segments: const [
      ButtonSegment(
        value: 'shopping',
        icon: Icon(Icons.shopping_basket_outlined),
        label: Text('Shopping'),
      ),
      ButtonSegment(
        value: 'pantry',
        icon: Icon(Icons.kitchen_outlined),
        label: Text('Pantry'),
      ),
    ],
    selected: {shopSection},
    onSelectionChanged: (value) =>
        updateFeatures(() => shopSection = value.first),
  );

  Future<void> editPantryItem([PantryItem? item]) async {
    final name = TextEditingController(text: item?.name ?? '');
    final quantity = TextEditingController(
      text: item?.quantitySpecified == true ? '${item!.quantity}' : '',
    );
    final unit = TextEditingController(
      text: item?.quantitySpecified == true ? item!.unit : '',
    );
    final result = await showDialog<PantryItem>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item == null ? 'Add pantry item' : 'Edit pantry item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Ingredient'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Quantity (optional)',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: unit,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      hintText: 'g, ml, whole…',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final amount = double.tryParse(quantity.text.trim());
              if (name.text.trim().isEmpty ||
                  (quantity.text.trim().isNotEmpty &&
                      (amount == null || amount <= 0))) {
                message('Enter an ingredient and a positive quantity.');
                return;
              }
              Navigator.pop(
                context,
                PantryItem(
                  id: item?.id,
                  name: name.text.trim(),
                  quantity: amount ?? 0,
                  unit: amount == null
                      ? 'as needed'
                      : unit.text.trim().isEmpty
                      ? 'whole'
                      : unit.text.trim(),
                  quantitySpecified: amount != null,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(seconds: 1), () {
      name.dispose();
      quantity.dispose();
      unit.dispose();
    });
    if (result == null) return;
    await run(() async {
      await db!.savePantryItem(result);
      await reload();
    });
  }

  Future<void> removePantryItem(PantryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove pantry item?'),
        content: Text('Remove ${item.name} from your pantry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await run(() async {
      await db!.deletePantryItem(item.id!);
      await reload();
    });
  }

  Future<void> importPantryPhoto(ImageSource source) async {
    XFile? photo;
    final isCamera = source == ImageSource.camera;
    try {
      if (isCamera) await db!.setSetting('pending_pantry_camera', 'true');
      photo = await ImagePicker().pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );
    } catch (_) {
      message(
        source == ImageSource.camera
            ? 'The camera could not open. Check camera permission and try again.'
            : 'The photo picker could not open. Please try again.',
      );
      return;
    } finally {
      if (isCamera) {
        await db!.setSetting('pending_pantry_camera', 'false');
      }
    }
    if (photo == null || !mounted) return;
    final bytes = await photo.readAsBytes();
    await reviewPantryImage(bytes, photo.mimeType ?? 'image/jpeg');
  }

  Future<void> recoverLostPantryPhoto() async {
    if (await db!.setting('pending_pantry_camera') != 'true') return;
    final response = await ImagePicker().retrieveLostData();
    await db!.setSetting('pending_pantry_camera', 'false');
    final photo = response.files?.firstOrNull;
    if (photo == null || !mounted) return;
    await reviewPantryImage(
      await photo.readAsBytes(),
      photo.mimeType ?? 'image/jpeg',
    );
  }

  Future<void> reviewPantryImage(Uint8List bytes, String mimeType) async {
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      message('Choose a clear photo smaller than 10 MB.');
      return;
    }
    List<Ingredient>? detected;
    await run(() async {
      detected = await ai.detectPantry(bytes, mimeType: mimeType);
    });
    if (!mounted || detected == null) return;
    if (detected!.isEmpty) {
      message('No pantry ingredients were detected in that photo.');
      return;
    }
    final unique = <String, Ingredient>{};
    for (final item in detected!) {
      if (item.name.trim().isEmpty) continue;
      final key =
          '${GroceryAggregator.canonicalName(item.name)}|${normalized(item.unit)}';
      unique.putIfAbsent(key, () => item);
      if (unique.length == 60) break;
    }
    detected = unique.values.toList();
    final selected = List<bool>.filled(detected!.length, true);
    var replaceExisting = true;
    final accepted = await showDialog<List<Ingredient>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Review detected items'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: replaceExisting,
                  onChanged: (value) =>
                      update(() => replaceExisting = value ?? true),
                  title: const Text('Replace matching pantry amounts'),
                  subtitle: const Text(
                    'Turn this off to add detected quantities to existing amounts.',
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: detected!.length,
                    itemBuilder: (context, index) {
                      final item = detected![index];
                      final existing = pantryItems
                          .where(
                            (stored) =>
                                GroceryAggregator.canonicalName(stored.name) ==
                                    GroceryAggregator.canonicalName(
                                      item.name,
                                    ) &&
                                normalized(stored.unit) ==
                                    normalized(item.unit),
                          )
                          .firstOrNull;
                      return CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: selected[index],
                        onChanged: (value) =>
                            update(() => selected[index] = value ?? false),
                        title: Text(item.name),
                        subtitle: Text(
                          '${displayAmount(item)}${existing == null ? '' : ' · currently ${displayAmount(existing.ingredient)}'}',
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, [
                for (var i = 0; i < detected!.length; i++)
                  if (selected[i]) detected![i],
              ]),
              child: const Text('Add selected'),
            ),
          ],
        ),
      ),
    );
    if (accepted == null || accepted.isEmpty) return;
    var savedCount = 0;
    await run(() async {
      for (final ingredient in accepted) {
        try {
          final name = ingredient.name.trim();
          if (name.isEmpty) continue;
          final quantitySpecified =
              ingredient.quantitySpecified &&
              ingredient.quantity.isFinite &&
              ingredient.quantity > 0;
          final unit = ingredient.unit.trim().isEmpty
              ? quantitySpecified
                    ? 'whole'
                    : 'as needed'
              : ingredient.unit.trim();
          final existing = pantryItems
              .where(
                (stored) =>
                    GroceryAggregator.canonicalName(stored.name) ==
                        GroceryAggregator.canonicalName(name) &&
                    normalized(stored.unit) == normalized(unit),
              )
              .firstOrNull;
          final addQuantities =
              !replaceExisting &&
              existing?.quantitySpecified == true &&
              quantitySpecified;
          await db!.savePantryItem(
            PantryItem(
              id: existing?.id,
              name: name,
              quantity: addQuantities
                  ? existing!.quantity + ingredient.quantity
                  : quantitySpecified
                  ? ingredient.quantity
                  : 0,
              unit: unit,
              quantitySpecified: quantitySpecified,
            ),
          );
          savedCount++;
        } on FormatException {
          // Keep valid detections when a provider returns one malformed row.
        }
      }
      await reload();
    });
    if (savedCount == 0) {
      message('None of the selected detections could be added.');
      return;
    }
    message('$savedCount pantry item${savedCount == 1 ? '' : 's'} added.');
  }

  Widget pantry() => page([
    shopSwitcher(),
    const SizedBox(height: 20),
    heading(
      'USE WHAT YOU HAVE',
      'Your pantry.',
      'Items here are deducted from shopping lists. Quantities are optional.',
    ),
    Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        FilledButton.icon(
          onPressed: busy ? null : () => editPantryItem(),
          icon: const Icon(Icons.add),
          label: const Text('Add item'),
        ),
        if (Platform.isAndroid || Platform.isIOS)
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () => importPantryPhoto(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Take photo'),
          ),
        OutlinedButton.icon(
          onPressed: busy ? null : () => importPantryPhoto(ImageSource.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Choose photo'),
        ),
      ],
    ),
    const SizedBox(height: 20),
    if (pantryItems.isEmpty)
      const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Your pantry is empty. Add staples manually or scan a shelf with a photo.',
          ),
        ),
      ),
    for (final item in pantryItems)
      Card(
        child: ListTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: Text(item.name),
          subtitle: Text(
            item.quantitySpecified
                ? displayAmount(item.ingredient)
                : 'Available — quantity not tracked',
          ),
          onTap: () => editPantryItem(item),
          trailing: IconButton(
            tooltip: 'Remove',
            onPressed: busy ? null : () => removePantryItem(item),
            icon: const Icon(Icons.delete_outline),
          ),
        ),
      ),
    if (pantryItems.isNotEmpty)
      const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'Quantity-free items cover unmeasured recipe needs. Measured pantry amounts are subtracted only when units are compatible.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ),
  ]);
}
