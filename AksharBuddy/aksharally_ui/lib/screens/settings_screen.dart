import 'package:flutter/material.dart';
import '../theme/ui_accessibility.dart';
import '../theme/app_settings.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/tts_service.dart';
import '../widgets/buddy_brand.dart';
import '../widgets/reading_customize_sheet.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _url = TextEditingController(text: AppSettings.effectiveBackendUrl);
  String? _message;
  bool _busy = false;
  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _change(VoidCallback change) {
    UIAccessibility.change(change);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
          ),
        ),
        OutlinedButton.icon(
          onPressed: () => showReadingCustomizeSheet(
            context,
            onChanged: () {
              if (mounted) setState(() {});
            },
          ),
          icon: const Icon(Icons.text_fields),
          label: const Text('Reading fonts, spacing and colours'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.record_voice_over),
          label: const Text('Android voice settings'),
          onPressed: () async {
            try {
              await TTSService.openVoiceSettings();
            } catch (_) {
              if (mounted) {
                setState(
                  () => _message =
                      'Open Android Settings > Text-to-speech. Install English, Hindi or Marathi voice data.',
                );
              }
            }
          },
        ),
        const BuddyHeading(
          'Make it yours',
          'There is no single right way to read.',
        ),
        BuddyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A comfortable page',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
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
                          (choice) => ChoiceChip(
                            label: Text(choice.$2),
                            selected:
                                UIAccessibility.activeColorTheme == choice.$1,
                            onSelected: (_) => _change(() {
                              UIAccessibility.activeColorTheme = choice.$1;
                              UIAccessibility.backgroundColor =
                                  UIAccessibility.themeBg(choice.$1);
                              UIAccessibility.textColor =
                                  UIAccessibility.themeText(choice.$1);
                            }),
                          ),
                        )
                        .toList(),
              ),
              const SizedBox(height: 20),
              const Text('Interface font'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: UIAccessibility.fonts
                    .map(
                      (font) => ChoiceChip(
                        label: Text(
                          font == 'System Default' ? 'Clear sans serif' : font,
                        ),
                        selected: UIAccessibility.fontFamily == font,
                        onSelected: (_) =>
                            _change(() => UIAccessibility.fontFamily = font),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
              Text('Text size · ${UIAccessibility.fontSize.round()}'),
              Slider(
                value: UIAccessibility.fontSize.clamp(14, 24),
                min: 14,
                max: 24,
                divisions: 10,
                label: '${UIAccessibility.fontSize.round()}',
                onChanged: (v) => _change(() => UIAccessibility.fontSize = v),
              ),
              Text(
                'Line spacing · ${UIAccessibility.lineHeight.toStringAsFixed(1)}',
              ),
              Slider(
                value: UIAccessibility.lineHeight.clamp(1.4, 2.0),
                min: 1.4,
                max: 2.0,
                divisions: 6,
                label: UIAccessibility.lineHeight.toStringAsFixed(1),
                onChanged: (v) => _change(() => UIAccessibility.lineHeight = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Bold interface text'),
                value: UIAccessibility.boldTextEnabled,
                onChanged: (v) =>
                    _change(() => UIAccessibility.boldTextEnabled = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Reduce motion'),
                value: UIAccessibility.reducedAnimationsEnabled,
                onChanged: (v) =>
                    _change(() => UIAccessibility.reducedAnimationsEnabled = v),
              ),
              const SizedBox(height: 8),
              const Text(
                'Reader font, spacing, colour and focus tools are under Reading appearance on each passage.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        BuddyCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reading language',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [('en', 'English'), ('hi', 'Hindi'), ('mr', 'Marathi')]
                    .map(
                      (l) => ChoiceChip(
                        label: Text(l.$2),
                        selected: AppSettings.language == l.$1,
                        onSelected: (_) async {
                          try {
                            await AppSettings.setLanguage(l.$1);
                            if (mounted) setState(() {});
                          } catch (_) {
                            if (mounted) {
                              setState(
                                () => _message =
                                    'Could not save the language. Try again.',
                              );
                            }
                          }
                        },
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
              const Text(
                'You can choose a different language for any document.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ExpansionTile(
          initiallyExpanded: true,
          title: const Text('Laptop connection'),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Your connection',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Start the backend on your laptop. Connect both devices to the same Wi-Fi or hotspot; internet and USB are not needed. Enter the address shown by the laptop launcher.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Backend URL',
                    hintText: 'http://192.168.1.10:5000',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            await AppSettings.setBackendUrl(_url.text);
                            await ApiService.checkConnection();
                            if (mounted) {
                              setState(
                                () => _message =
                                    'Connected to your laptop. Ready for OCR and local AI.',
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              setState(
                                () => _message = e is FormatException
                                    ? e.message
                                    : e.toString().replaceFirst(
                                        'Exception: ',
                                        '',
                                      ),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  child: const Text('Save and check connection'),
                ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Semantics(liveRegion: true, child: Text(_message!)),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Text(
          'Saved readings, words, and your place stay on this device. They are shared by accounts using this app installation; signing out does not erase them.',
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () async {
            try {
              await AuthService().logout();
              if (context.mounted) {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/login',
                  (_) => false,
                );
              }
            } catch (_) {
              if (mounted) {
                setState(
                  () => _message = 'Could not sign out. Please try again.',
                );
              }
            }
          },
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ],
    ),
  );
}
