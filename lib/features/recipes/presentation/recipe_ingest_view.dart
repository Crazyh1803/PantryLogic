part of '../../../main.dart';

extension _RecipeIngestView on _HomeState {
  void focusCaption() {
    updateFeatures(() => showCaption = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = captionAnchor.currentContext;
      if (target != null)
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 250),
          alignment: 0.2,
        );
      captionFocus.requestFocus();
    });
  }

  void showAiFailure(Object error, {bool fromLink = false}) {
    final failure = AiExceptionHandler.describe(error, fromLink: fromLink);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(failure.message),
        duration: const Duration(seconds: 8),
        action: failure.action == AiErrorAction.none
            ? null
            : SnackBarAction(
                label: failure.action == AiErrorAction.settings
                    ? 'Go to Settings'
                    : 'Paste Text',
                onPressed: () {
                  if (failure.action == AiErrorAction.settings) {
                    updateFeatures(() {
                      tab = 4;
                      settingsSection = 'ai';
                    });
                  } else {
                    updateFeatures(() => tab = 3);
                    focusCaption();
                  }
                },
              ),
      ),
    );
  }

  Widget ingestView() => page([
    heading(
      'FROM SAVED POST TO DINNER',
      'Bring a recipe home.',
      'Start with a link, caption or screenshot. Combine them when a recipe needs more context.',
    ),
    SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'url', icon: Icon(Icons.link), label: Text('URL')),
        ButtonSegment(
          value: 'text',
          icon: Icon(Icons.notes),
          label: Text('Text'),
        ),
        ButtonSegment(
          value: 'image',
          icon: Icon(Icons.image_outlined),
          label: Text('Image'),
        ),
      ],
      selected: {ingestMode},
      onSelectionChanged: (v) => updateFeatures(() {
        ingestMode = v.single;
        if (ingestMode == 'text') showCaption = true;
      }),
    ),
    const SizedBox(height: 16),
    if (ingestMode == 'url')
      TextField(
        controller: urlField,
        keyboardType: TextInputType.url,
        autocorrect: false,
        decoration: const InputDecoration(
          labelText: 'Recipe URL',
          hintText: 'https://www.instagram.com/reel/…',
        ),
      ),
    if (ingestMode != 'url' && urlField.text.trim().isNotEmpty)
      ListTile(
        leading: const Icon(Icons.link),
        title: Text(
          urlField.text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: const Text('Included as source'),
        trailing: IconButton(
          tooltip: 'Remove URL',
          onPressed: () => updateFeatures(() => urlField.clear()),
          icon: const Icon(Icons.close),
        ),
      ),
    if (ingestMode == 'image' || showCaption)
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: busy ? null : pickImage,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Choose image / screenshot'),
        ),
      ),
    if (imageBytes != null)
      Card(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Image.memory(
                imageBytes!,
                height: 160,
                errorBuilder: (_, _, _) => const Text(
                  'Preview unavailable; choose another image if needed.',
                ),
              ),
            ),
            ListTile(
              title: Text(imageName ?? 'Screenshot'),
              subtitle: const Text('Included with your caption / notes'),
              trailing: IconButton(
                tooltip: 'Remove image',
                onPressed: () => updateFeatures(() {
                  imageBytes = null;
                  imageName = null;
                }),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    if (ingestFailure != null)
      Card(
        color: const Color(0xFFFFF1D7),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ingestFailure!.action == AiErrorAction.pasteText &&
                        urlField.text.trim().isNotEmpty
                    ? 'No recipe text found in this post. Paste the caption or upload a screenshot of the ingredients list.'
                    : ingestFailure!.message,
              ),
              if (ingestFailure!.action == AiErrorAction.settings)
                TextButton(
                  onPressed: () => updateFeatures(() {
                    tab = 4;
                    settingsSection = 'ai';
                  }),
                  child: const Text('Go to Settings'),
                ),
              if (ingestFailure!.action == AiErrorAction.pasteText)
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: focusCaption,
                      child: const Text('Paste Text'),
                    ),
                    TextButton(
                      onPressed: busy ? null : pickImage,
                      child: const Text('Upload screenshot'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    if (showCaption || ingestMode == 'text' || raw.text.trim().isNotEmpty)
      Padding(
        key: captionAnchor,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: TextField(
          controller: raw,
          focusNode: captionFocus,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Recipe Text / Caption / Notes',
            hintText:
                'Paste a video caption, ingredients list, or your own notes here...',
            alignLabelWithHint: true,
          ),
        ),
      )
    else
      TextButton.icon(
        onPressed: focusCaption,
        icon: const Icon(Icons.add),
        label: const Text('Add caption or notes'),
      ),
    FilledButton.icon(
      onPressed: busy ? null : importRecipe,
      icon: const Icon(Icons.auto_awesome_outlined),
      label: Text(busy ? 'Reading recipe…' : 'Extract & review'),
    ),
    const SizedBox(height: 16),
    const Text(
      'Structured captions can be parsed on this device. Other text and images go to your selected AI provider and enabled backups. A video-only or sign-in-only link may need a pasted caption or screenshots.',
      style: TextStyle(height: 1.5, color: Colors.black54),
    ),
    TextButton(
      onPressed: () => edit(),
      child: const Text('Enter a recipe manually'),
    ),
  ]);
}
