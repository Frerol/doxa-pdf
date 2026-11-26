// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

import '../../l10n/gen/app_localizations.dart';
import '../dictionary/dictionaries_page.dart';
import '../dictionary/dictionary_library.dart';
import '../reader/color_mode.dart';
import '../reader/reader_geometry.dart';
import 'app_settings.dart';

/// Swatches offered for the custom page colours (FR-VIEW-016).
const customBackgrounds = [
  Color(0xFF1E2A33),
  Color(0xFF000000),
  Color(0xFF2B2B2B),
  Color(0xFF1B3A2F),
  Color(0xFFFFF8E1),
  Color(0xFFE8F5E9),
  Color(0xFFE3F2FD),
  Color(0xFFFFFFFF),
];
const customTexts = [
  Color(0xFFE6E1D3),
  Color(0xFFFFFFFF),
  Color(0xFFB0BEC5),
  Color(0xFFFFE082),
  Color(0xFF000000),
  Color(0xFF3E2723),
  Color(0xFF0D47A1),
  Color(0xFF1B5E20),
];

/// App settings (docs/plan/05-ux-design.md §2): appearance, language and
/// reading.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.settings});
  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ValueListenableBuilder(
        valueListenable: settings,
        builder: (context, value, _) => ListView(
          children: [
            _Header(l10n.settingsAppearance),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SegmentedButton<ThemeMode>(
                segments: [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text(l10n.themeSystem),
                    icon: const Icon(Icons.brightness_auto),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text(l10n.themeLight),
                    icon: const Icon(Icons.light_mode),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text(l10n.themeDark),
                    icon: const Icon(Icons.dark_mode),
                  ),
                ],
                selected: {value.themeMode},
                onSelectionChanged: (selection) => settings.update(
                  value.copyWith(themeMode: selection.single),
                ),
              ),
            ),
            SwitchListTile(
              title: Text(l10n.settingsDynamicColor),
              subtitle: Text(l10n.settingsDynamicColorHint),
              value: value.dynamicColor,
              onChanged: (on) =>
                  settings.update(value.copyWith(dynamicColor: on)),
            ),
            _Header(l10n.settingsLanguage),
            RadioGroup<String>(
              groupValue: value.languageCode ?? '',
              onChanged: (code) => settings.update(
                value.copyWith(
                  languageCode: () =>
                      code == null || code.isEmpty ? null : code,
                ),
              ),
              child: Column(
                children: [
                  RadioListTile(value: '', title: Text(l10n.languageSystem)),
                  // Language names are written in their own language.
                  const RadioListTile(value: 'en', title: Text('English')),
                  const RadioListTile(
                    value: 'pt',
                    title: Text('Português (Brasil)'),
                  ),
                ],
              ),
            ),
            _Header(l10n.settingsReading),
            ListTile(title: Text(l10n.settingsFitMode)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<FitMode>(
                segments: [
                  ButtonSegment(
                    value: FitMode.page,
                    label: Text(l10n.readerFitPage),
                  ),
                  ButtonSegment(
                    value: FitMode.width,
                    label: Text(l10n.readerFitWidth),
                  ),
                ],
                selected: {value.fitMode},
                onSelectionChanged: (selection) =>
                    settings.update(value.copyWith(fitMode: selection.single)),
              ),
            ),
            ListTile(title: Text(l10n.settingsPageColors)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: PageColorModeSelector(
                mode: value.colorMode,
                onChanged: (mode) =>
                    settings.update(value.copyWith(colorMode: mode)),
              ),
            ),
            if (value.colorMode == PageColorMode.custom)
              CustomColorsEditor(settings: settings),
            SwitchListTile(
              title: Text(l10n.settingsKeepScreenOn),
              value: value.keepScreenOn,
              onChanged: (on) =>
                  settings.update(value.copyWith(keepScreenOn: on)),
            ),
            if (DictionaryScope.maybeOf(context) case final scope?)
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(l10n.dictionariesTitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DictionariesPage(
                      library: scope.library,
                      openUri: scope.openUri,
                      importer: scope.importer,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Normal, night, sepia and custom page colours (FR-VIEW-005, FR-VIEW-016).
class PageColorModeSelector extends StatelessWidget {
  const PageColorModeSelector({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final PageColorMode mode;
  final ValueChanged<PageColorMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SegmentedButton<PageColorMode>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(
          value: PageColorMode.normal,
          label: Text(l10n.colorNormal),
        ),
        ButtonSegment(value: PageColorMode.night, label: Text(l10n.colorNight)),
        ButtonSegment(value: PageColorMode.sepia, label: Text(l10n.colorSepia)),
        ButtonSegment(
          value: PageColorMode.custom,
          label: Text(l10n.colorCustom),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (selection) => onChanged(selection.single),
    );
  }
}

/// Background and text swatches for the custom page colours (FR-VIEW-016),
/// shared by Settings and the reader's view options.
class CustomColorsEditor extends StatelessWidget {
  const CustomColorsEditor({super.key, required this.settings});
  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ValueListenableBuilder(
      valueListenable: settings,
      builder: (context, value, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Swatches(
            label: l10n.settingsCustomBackground,
            colors: customBackgrounds,
            selected: value.customBackground,
            onSelected: (color) =>
                settings.update(value.copyWith(customBackground: color)),
          ),
          _Swatches(
            label: l10n.settingsCustomText,
            colors: customTexts,
            selected: value.customText,
            onSelected: (color) =>
                settings.update(value.copyWith(customText: color)),
          ),
        ],
      ),
    );
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches({
    required this.label,
    required this.colors,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final List<Color> colors;
  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (i, color) in colors.indexed)
                Semantics(
                  button: true,
                  selected: color == selected,
                  label: '$label ${i + 1}',
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => onSelected(color),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color == selected ? primary : outline,
                          width: color == selected ? 3 : 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}
