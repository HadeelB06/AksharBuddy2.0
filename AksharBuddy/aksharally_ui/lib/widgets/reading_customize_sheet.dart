import 'package:flutter/material.dart';
import '../theme/accessibility_settings.dart';
import 'highlighted_text_view.dart';

Future<void> showReadingCustomizeSheet(
  BuildContext context, {
  required VoidCallback onChanged,
  String detectedText = '',
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        void update(VoidCallback fn) {
          setSheet(() {
            fn();
            AccessibilitySettings.profile = 'customize';
          });
          onChanged();
        }

        Widget slider(
          String label,
          double value,
          double min,
          double max,
          int divisions,
          ValueChanged<double> change,
        ) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$label · ${value.toStringAsFixed(1)}'),
            Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              label: value.toStringAsFixed(1),
              onChanged: (v) => update(() => change(v)),
            ),
          ],
        );
        return SizedBox(
          height: MediaQuery.sizeOf(ctx).height * .9,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Reading appearance',
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close appearance',
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Choose what feels comfortable. These controls change the page, not your words.',
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: AccessibilitySettings.fontFamily,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Reading font'),
                  items: AccessibilitySettings.fonts
                      .toSet()
                      .map(
                        (f) => DropdownMenuItem(
                          value: f,
                          child: Text(
                            f == 'System Default' ? 'Clear sans serif' : f,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      update(() => AccessibilitySettings.fontFamily = v);
                    }
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  'Clear sans serif and OpenDyslexic work offline. Other fonts may download when selected.',
                ),
                const SizedBox(height: 20),
                slider(
                  'Text size',
                  AccessibilitySettings.fontSize,
                  16,
                  36,
                  20,
                  (v) => AccessibilitySettings.fontSize = v,
                ),
                slider(
                  'Line spacing',
                  AccessibilitySettings.lineHeight,
                  1.2,
                  2.4,
                  12,
                  (v) => AccessibilitySettings.lineHeight = v,
                ),
                ExpansionTile(
                  title: const Text('More spacing options'),
                  children: [
                    slider(
                      'Letter spacing',
                      AccessibilitySettings.letterSpacing,
                      0,
                      4,
                      16,
                      (v) => AccessibilitySettings.letterSpacing = v,
                    ),
                    slider(
                      'Word spacing',
                      AccessibilitySettings.wordSpacing,
                      2,
                      16,
                      14,
                      (v) => AccessibilitySettings.wordSpacing = v,
                    ),
                    slider(
                      'Paragraph spacing',
                      AccessibilitySettings.paragraphSpacing,
                      8,
                      48,
                      10,
                      (v) => AccessibilitySettings.paragraphSpacing = v,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Page colour', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      [
                            ('cream_black', 'Paper'),
                            ('white_black', 'White'),
                            ('pale_blue_navy', 'Blue'),
                            ('dark_mode', 'Dark'),
                          ]
                          .map(
                            (v) => ChoiceChip(
                              label: Text(v.$2),
                              selected:
                                  AccessibilitySettings.colorTheme == v.$1,
                              onSelected: (_) => update(
                                () => AccessibilitySettings.colorTheme = v.$1,
                              ),
                            ),
                          )
                          .toList(),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Highlight spoken words'),
                  value: AccessibilitySettings.wordHighlighting,
                  onChanged: (v) =>
                      update(() => AccessibilitySettings.wordHighlighting = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Focus band'),
                  value: AccessibilitySettings.focusLineMode,
                  onChanged: (v) =>
                      update(() => AccessibilitySettings.focusLineMode = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Reading ruler'),
                  value: AccessibilitySettings.readingRuler,
                  onChanged: (v) =>
                      update(() => AccessibilitySettings.readingRuler = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('English syllable hints'),
                  subtitle: const Text(
                    'Approximate visual hints; your original text is preserved.',
                  ),
                  value: AccessibilitySettings.syllableBreakdown,
                  onChanged: (v) =>
                      update(() => AccessibilitySettings.syllableBreakdown = v),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AccessibilitySettings.backgroundColor(),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: HighlightedTextView(
                    text: 'A little reading, at your pace.',
                    words: HighlightedTextView.splitToWords(
                      'A little reading, at your pace.',
                    ),
                    currentIndex: -1,
                  ),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => update(() {
                    AccessibilitySettings.fontFamily = 'System Default';
                    AccessibilitySettings.fontSize = 22;
                    AccessibilitySettings.lineHeight = 1.6;
                    AccessibilitySettings.letterSpacing = 0;
                    AccessibilitySettings.wordSpacing = 4;
                    AccessibilitySettings.paragraphSpacing = 16;
                    AccessibilitySettings.colorTheme = 'cream_black';
                    AccessibilitySettings.syllableBreakdown = false;
                  }),
                  child: const Text('Reset reading appearance'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await AccessibilitySettings.save();
                      if (ctx.mounted) Navigator.pop(ctx);
                    } catch (_) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not save your reading preferences.',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Save reading preferences'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  onChanged();
}
