// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:doxa_dict/doxa_dict.dart' show foldDiacritics;
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

/// The categories of Settings (UX §7). A category appears only when it
/// has settings: Tabs, Annotating and Stylus join when they have some.
enum SettingsCategory { general, viewing }

/// One setting: where it lives, the words search matches, and its row.
typedef _Setting = ({
  SettingsCategory category,
  String Function(AppLocalizations l10n) section,
  String Function(AppLocalizations l10n) title,
  String Function(AppLocalizations l10n) description,
  Widget Function(BuildContext context, SettingsController settings) build,
});

final List<_Setting> _settings = [
  (
    category: SettingsCategory.general,
    section: (l10n) => l10n.settingsAppearance,
    title: (l10n) => l10n.settingsTheme,
    description: (l10n) => l10n.settingsThemeHint,
    build: (context, settings) {
      final l10n = AppLocalizations.of(context);
      return _ChoiceTile<ThemeMode>(
        title: l10n.settingsTheme,
        description: l10n.settingsThemeHint,
        value: settings.value.themeMode,
        choices: {
          ThemeMode.system: l10n.themeSystem,
          ThemeMode.light: l10n.themeLight,
          ThemeMode.dark: l10n.themeDark,
        },
        onChanged: (mode) =>
            settings.update(settings.value.copyWith(themeMode: mode)),
      );
    },
  ),
  (
    category: SettingsCategory.general,
    section: (l10n) => l10n.settingsAppearance,
    title: (l10n) => l10n.settingsDynamicColor,
    description: (l10n) => l10n.settingsDynamicColorHint,
    build: (context, settings) {
      final l10n = AppLocalizations.of(context);
      return SwitchListTile(
        title: Text(l10n.settingsDynamicColor),
        subtitle: Text(l10n.settingsDynamicColorHint),
        value: settings.value.dynamicColor,
        onChanged: (on) =>
            settings.update(settings.value.copyWith(dynamicColor: on)),
      );
    },
  ),
  (
    category: SettingsCategory.general,
    section: (l10n) => l10n.settingsLanguage,
    title: (l10n) => l10n.settingsLanguage,
    description: (l10n) => l10n.settingsLanguageHint,
    build: (context, settings) {
      final l10n = AppLocalizations.of(context);
      return _ChoiceTile<String>(
        title: l10n.settingsLanguage,
        description: l10n.settingsLanguageHint,
        value: settings.value.languageCode ?? '',
        choices: {
          '': l10n.languageSystem,
          // Language names are written in their own language.
          'en': 'English',
          'pt': 'Português (Brasil)',
        },
        onChanged: (code) => settings.update(
          settings.value.copyWith(
            languageCode: () => code.isEmpty ? null : code,
          ),
        ),
      );
    },
  ),
  (
    category: SettingsCategory.general,
    section: (l10n) => l10n.settingsScreen,
    title: (l10n) => l10n.settingsKeepScreenOn,
    description: (l10n) => l10n.settingsKeepScreenOnHint,
    build: (context, settings) {
      final l10n = AppLocalizations.of(context);
      return SwitchListTile(
        title: Text(l10n.settingsKeepScreenOn),
        subtitle: Text(l10n.settingsKeepScreenOnHint),
        value: settings.value.keepScreenOn,
        onChanged: (on) =>
            settings.update(settings.value.copyWith(keepScreenOn: on)),
      );
    },
  ),
  (
    category: SettingsCategory.viewing,
    section: (l10n) => l10n.settingsReading,
    title: (l10n) => l10n.settingsFitMode,
    description: (l10n) => l10n.settingsFitModeHint,
    build: (context, settings) {
      final l10n = AppLocalizations.of(context);
      return _ChoiceTile<FitMode>(
        title: l10n.settingsFitMode,
        description: l10n.settingsFitModeHint,
        value: settings.value.fitMode,
        choices: {
          FitMode.page: l10n.readerFitPage,
          FitMode.width: l10n.readerFitWidth,
        },
        onChanged: (mode) =>
            settings.update(settings.value.copyWith(fitMode: mode)),
      );
    },
  ),
  (
    category: SettingsCategory.viewing,
    section: (l10n) => l10n.settingsReading,
    title: (l10n) => l10n.settingsZoomOutPastFit,
    description: (l10n) => l10n.settingsZoomOutPastFitHint,
    build: (context, settings) {
      final l10n = AppLocalizations.of(context);
      return SwitchListTile(
        title: Text(l10n.settingsZoomOutPastFit),
        subtitle: Text(l10n.settingsZoomOutPastFitHint),
        value: settings.value.zoomOutPastFit,
        onChanged: (on) =>
            settings.update(settings.value.copyWith(zoomOutPastFit: on)),
      );
    },
  ),
  (
    category: SettingsCategory.viewing,
    section: (l10n) => l10n.settingsReading,
    title: (l10n) => l10n.settingsPageColors,
    description: (l10n) => l10n.settingsPageColorsHint,
    build: (context, settings) {
      final l10n = AppLocalizations.of(context);
      final value = settings.value;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ChoiceTile<PageColorMode>(
            title: l10n.settingsPageColors,
            description: l10n.settingsPageColorsHint,
            value: value.colorMode,
            choices: {
              PageColorMode.normal: l10n.colorNormal,
              PageColorMode.night: l10n.colorNight,
              PageColorMode.sepia: l10n.colorSepia,
              PageColorMode.custom: l10n.colorCustom,
            },
            onChanged: (mode) =>
                settings.update(settings.value.copyWith(colorMode: mode)),
          ),
          if (value.colorMode == PageColorMode.custom)
            CustomColorsEditor(settings: settings),
        ],
      );
    },
  ),
  (
    category: SettingsCategory.viewing,
    section: (l10n) => l10n.settingsPageTurning,
    title: (l10n) => l10n.optionTapZones,
    description: (l10n) => l10n.optionTapZonesHint,
    build: (context, settings) {
      final l10n = AppLocalizations.of(context);
      return SwitchListTile(
        title: Text(l10n.optionTapZones),
        subtitle: Text(l10n.optionTapZonesHint),
        value: settings.value.tapZones,
        onChanged: (on) =>
            settings.update(settings.value.copyWith(tapZones: on)),
      );
    },
  ),
  (
    category: SettingsCategory.viewing,
    section: (l10n) => l10n.settingsPageTurning,
    title: (l10n) => l10n.optionKeepZoom,
    description: (l10n) => l10n.optionKeepZoomHint,
    build: (context, settings) {
      final l10n = AppLocalizations.of(context);
      return SwitchListTile(
        title: Text(l10n.optionKeepZoom),
        subtitle: Text(l10n.optionKeepZoomHint),
        value: settings.value.keepZoomOnTurn,
        onChanged: (on) =>
            settings.update(settings.value.copyWith(keepZoomOnTurn: on)),
      );
    },
  ),
];

String _categoryName(AppLocalizations l10n, SettingsCategory category) =>
    switch (category) {
      SettingsCategory.general => l10n.settingsGeneral,
      SettingsCategory.viewing => l10n.settingsViewing,
    };

/// Case- and accent-insensitive words, so "cor" finds "Cores" and "tela"
/// finds "Tela".
String _searchKey(String text) => foldDiacritics(text.trim());

/// App settings (docs/plan/05-ux-design.md §7 "Settings"): a search field,
/// then the categories, each opening its own page.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings});
  final SettingsController settings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(BuildContext context, SettingsCategory category) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              _CategoryPage(category: category, settings: widget.settings),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dictionaries = DictionaryScope.maybeOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.settings, _search]),
        builder: (context, _) {
          final query = _searchKey(_search.text);
          final field = Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchBar(
              controller: _search,
              hintText: l10n.settingsSearchHint,
              leading: const Icon(Icons.search),
              trailing: [
                if (_search.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: MaterialLocalizations.of(context)
                        .deleteButtonTooltip,
                    onPressed: _search.clear,
                  ),
              ],
            ),
          );
          if (query.isEmpty) {
            return ListView(
              children: [
                field,
                _CategoryTile(
                  icon: Icons.tune,
                  title: l10n.settingsGeneral,
                  summary: l10n.settingsGeneralSummary,
                  onTap: () => _open(context, SettingsCategory.general),
                ),
                _CategoryTile(
                  icon: Icons.chrome_reader_mode_outlined,
                  title: l10n.settingsViewing,
                  summary: l10n.settingsViewingSummary,
                  onTap: () => _open(context, SettingsCategory.viewing),
                ),
                if (dictionaries != null)
                  _CategoryTile(
                    icon: Icons.menu_book_outlined,
                    title: l10n.dictionariesTitle,
                    summary: l10n.settingsDictionariesSummary,
                    onTap: () => _openDictionaries(context, dictionaries),
                  ),
              ],
            );
          }
          bool matches(String text) => _searchKey(text).contains(query);
          final found = [
            for (final setting in _settings)
              if (matches(setting.title(l10n)) ||
                  matches(setting.description(l10n)))
                setting,
          ];
          final dictionariesFound =
              dictionaries != null &&
              (matches(l10n.dictionariesTitle) ||
                  matches(l10n.settingsDictionariesSummary));
          return ListView(
            children: [
              field,
              for (final category in SettingsCategory.values)
                if (found.where((s) => s.category == category).toList()
                    case final inCategory when inCategory.isNotEmpty) ...[
                  _Header(_categoryName(l10n, category)),
                  for (final setting in inCategory)
                    setting.build(context, widget.settings),
                ],
              if (dictionariesFound)
                _CategoryTile(
                  icon: Icons.menu_book_outlined,
                  title: l10n.dictionariesTitle,
                  summary: l10n.settingsDictionariesSummary,
                  onTap: () => _openDictionaries(context, dictionaries),
                ),
              if (found.isEmpty && !dictionariesFound)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.settingsNoResults(_search.text.trim()),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  void _openDictionaries(BuildContext context, DictionaryScope scope) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DictionariesPage(
            library: scope.library,
            openUri: scope.openUri,
            importer: scope.importer,
          ),
        ),
      );
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.icon,
    required this.title,
    required this.summary,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(summary),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

/// One category: its settings under their section headers.
class _CategoryPage extends StatelessWidget {
  const _CategoryPage({required this.category, required this.settings});

  final SettingsCategory category;
  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final inCategory = [
      for (final setting in _settings)
        if (setting.category == category) setting,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(_categoryName(l10n, category))),
      body: ValueListenableBuilder(
        valueListenable: settings,
        builder: (context, _, _) => ListView(
          children: [
            for (final (i, setting) in inCategory.indexed) ...[
              if (_startsSection(inCategory, i, l10n))
                _Header(setting.section(l10n)),
              setting.build(context, settings),
            ],
          ],
        ),
      ),
    );
  }
}

/// Whether the setting at [i] opens a new section that needs a header. A
/// section holding one setting of the same name (Language) needs none.
bool _startsSection(List<_Setting> settings, int i, AppLocalizations l10n) {
  final section = settings[i].section(l10n);
  if (i > 0 && settings[i - 1].section(l10n) == section) return false;
  final alone =
      i + 1 == settings.length || settings[i + 1].section(l10n) != section;
  return !(alone && settings[i].title(l10n) == section);
}

/// A setting with a few choices: the row shows the current one, and a tap
/// opens a dialog with all of them.
class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.description,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  final String title;
  final String description;
  final T value;
  final Map<T, String> choices;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title),
    subtitle: Text('${choices[value]} · $description'),
    onTap: () async {
      final chosen = await showDialog<T>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(title),
          children: [
            RadioGroup<T>(
              groupValue: value,
              onChanged: (choice) => Navigator.of(context).pop(choice),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final MapEntry(:key, value: label) in choices.entries)
                    RadioListTile<T>(value: key, title: Text(label)),
                ],
              ),
            ),
          ],
        ),
      );
      if (chosen != null && chosen != value) onChanged(chosen);
    },
  );
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
