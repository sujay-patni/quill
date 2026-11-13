import 'package:flutter/material.dart';

import 'reading_profile.dart';

// The reader's option sheets, arranged like Moon Reader's: Visual options (text, margins,
// page turn), Control options and Themes. Every change is applied at once through [onChanged].

typedef ProfileChanged = void Function(ReadingProfile profile);

/// [bookOnly] / [onBookOnly] add the "this book only" switch (native reader).
Future<void> showVisualOptions(
  BuildContext context,
  ReadingProfile profile,
  ProfileChanged onChanged, {
  bool? bookOnly,
  ValueChanged<bool>? onBookOnly,
}) {
  var own = bookOnly ?? false;
  return _sheet(
  context,
  (setSheet, get, set) {
    final p = get();
    return [
      if (bookOnly != null && onBookOnly != null)
        SwitchListTile(
          key: const Key('bookOnly'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Settings for this book only'),
          subtitle: const Text('Off: this book follows your usual settings'),
          value: own,
          onChanged: (v) {
            setSheet(() => own = v);
            onBookOnly(v);
          },
        ),
      _Group(
        onReset: () => set(p.resetText()),
        children: [
          _Stepper(
            label: 'Font size',
            value: p.fontSize,
            min: 8,
            max: 30,
            step: 0.5,
            format: (v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1),
            onChanged: (v) => set(p.copyWith(fontSize: v)),
          ),
          _Stepper(
            label: 'Paragraph spacing',
            value: p.paragraphSpacing.toDouble(),
            min: 0,
            max: 200,
            step: 10,
            format: (v) => '${v.round()}%',
            onChanged: (v) => set(p.copyWith(paragraphSpacing: v.round())),
          ),
          _Stepper(
            label: 'Line spacing',
            value: p.lineSpacing.toDouble(),
            min: 0,
            max: 10,
            step: 1,
            onChanged: (v) => set(p.copyWith(lineSpacing: v.round())),
          ),
          _Stepper(
            label: 'Font spacing',
            value: p.fontSpacing.toDouble(),
            min: 0,
            max: 10,
            step: 1,
            onChanged: (v) => set(p.copyWith(fontSpacing: v.round())),
          ),
          Row(
            children: [
              const Expanded(child: Text('Font')),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'serif', label: Text('Serif')),
                  ButtonSegment(value: 'sans-serif', label: Text('Sans')),
                  ButtonSegment(value: 'monospace', label: Text('Mono')),
                ],
                selected: {p.fontFamily},
                onSelectionChanged: (s) => set(p.copyWith(fontFamily: s.first)),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(label: const Text('Italic'), selected: p.italicText, onSelected: (v) => set(p.copyWith(italicText: v))),
              FilterChip(
                label: const Text('Underline'),
                selected: p.underlineText,
                onSelected: (v) => set(p.copyWith(underlineText: v)),
              ),
              FilterChip(label: const Text('Shadow'), selected: p.textShadow, onSelected: (v) => set(p.copyWith(textShadow: v))),
            ],
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Bold text'),
            value: p.boldText,
            onChanged: (v) => set(p.copyWith(boldText: v)),
          ),
          SwitchListTile(
            key: const Key('hyphenation'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Hyphenation'),
            subtitle: const Text('Break long words at line ends (English)'),
            value: p.hyphenation,
            onChanged: (v) => set(p.copyWith(hyphenation: v)),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Paper texture'),
            subtitle: const Text('Grain and fibres on the page, as in Moon Reader'),
            value: p.paperTexture,
            onChanged: (v) => set(p.copyWith(paperTexture: v)),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text("Use the book's own styles"),
            subtitle: const Text("Off: Quill's own pages in your layout. On: the page as the book was designed. Applies when the book is next opened"),
            value: p.publisherStyles,
            onChanged: (v) => set(p.copyWith(publisherStyles: v)),
          ),
        ],
      ),
      _Group(
        onReset: () => set(p.resetMargins()),
        children: [
          _Stepper(
            label: 'Left margin',
            value: p.sideMargin.toDouble(),
            min: 0,
            max: 80,
            step: 2,
            onChanged: (v) => set(p.copyWith(sideMargin: v.round())),
          ),
          _Stepper(
            label: 'Right margin',
            value: p.rightMargin.toDouble(),
            min: 0,
            max: 80,
            step: 2,
            onChanged: (v) => set(p.copyWith(rightMargin: v.round())),
          ),
          SwitchListTile(
            key: const Key('dualPage'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Two pages in landscape'),
            value: p.dualPage,
            onChanged: (v) => set(p.copyWith(dualPage: v)),
          ),
          _Stepper(
            label: 'Top margin',
            value: p.topMargin.toDouble(),
            min: 0,
            max: 120,
            step: 5,
            onChanged: (v) => set(p.copyWith(topMargin: v.round())),
          ),
          _Stepper(
            label: 'Bottom margin',
            value: p.bottomMargin.toDouble(),
            min: 20,
            max: 120,
            step: 5,
            onChanged: (v) => set(p.copyWith(bottomMargin: v.round())),
          ),
        ],
      ),
      _Group(
        children: [
          Row(
            children: [
              const Expanded(child: Text('Page turn')),
              SegmentedButton<PageTurn>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: PageTurn.curl, label: Text('Curl')),
                  ButtonSegment(value: PageTurn.slide, label: Text('Slide')),
                  ButtonSegment(value: PageTurn.none, label: Text('None')),
                ],
                selected: {p.pageTurn},
                onSelectionChanged: (s) => set(p.copyWith(pageTurn: s.first)),
              ),
            ],
          ),
          _Stepper(
            label: 'Page turn time',
            value: p.turnMillis.toDouble(),
            min: 150,
            max: 800,
            step: 50,
            format: (v) => '${v.round()} ms',
            onChanged: (v) => set(p.copyWith(turnMillis: v.round())),
          ),
          _Stepper(
            label: 'Warm filter',
            value: p.blueLight.toDouble(),
            min: 0,
            max: 100,
            step: 10,
            format: (v) => v == 0 ? 'Off' : '${v.round()}%',
            onChanged: (v) => set(p.copyWith(blueLight: v.round())),
          ),
        ],
      ),
    ];
  },
  profile,
  onChanged,
  title: 'Visual options',
);
}

Future<void> showControlOptions(BuildContext context, ReadingProfile profile, ProfileChanged onChanged) => _sheet(
  context,
  (setSheet, get, set) {
    final p = get();
    Widget toggle(String title, String subtitle, bool value, ReadingProfile Function(bool) change) => SwitchListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: (v) => set(change(v)),
    );
    return [
      _Group(
        children: [
          toggle(
            'Volume keys turn pages',
            'Volume down: next page · volume up: previous page',
            p.volumeKeys,
            (v) => p.copyWith(volumeKeys: v),
          ),
          toggle(
            'Brightness on the left edge',
            'Slide up or down along the left edge of the page',
            p.brightnessSwipe,
            (v) => p.copyWith(brightnessSwipe: v),
          ),
          toggle('Keep the screen on', 'While a book is open', p.keepAwake, (v) => p.copyWith(keepAwake: v)),
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Reading brightness'),
            subtitle: Text(p.brightness == null ? 'Follows the system' : '${(p.brightness! * 100).round()}%'),
            trailing: p.brightness == null
                ? null
                : TextButton(
                    onPressed: () => set(p.copyWith(brightness: () => null)),
                    child: const Text('Use system'),
                  ),
          ),
        ],
      ),
      const _Group(
        children: [
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('Taps'),
            subtitle: Text('Left: previous page · middle: options · right: next page'),
          ),
        ],
      ),
      _Group(
        children: [
          for (final (label, value, change) in <(String, ReaderAction, ReadingProfile Function(ReaderAction))>[
            ('Swipe up', p.swipeUp, (a) => p.copyWith(swipeUp: a)),
            ('Swipe down', p.swipeDown, (a) => p.copyWith(swipeDown: a)),
            ('Tap status bar, left', p.statusLeft, (a) => p.copyWith(statusLeft: a)),
            ('Tap status bar, right', p.statusRight, (a) => p.copyWith(statusRight: a)),
          ])
            Row(
              children: [
                Expanded(child: Text(label)),
                DropdownButton<ReaderAction>(
                  value: value,
                  underline: const SizedBox.shrink(),
                  items: [for (final a in ReaderAction.values) DropdownMenuItem(value: a, child: Text(a.label))],
                  onChanged: (a) => a == null ? null : set(change(a)),
                ),
              ],
            ),
        ],
      ),
      _Group(
        children: [
          _Stepper(
            label: 'Auto page turn every',
            value: p.autoTurnSeconds.toDouble(),
            min: 5,
            max: 180,
            step: 5,
            format: (v) => '${v.round()} s',
            onChanged: (v) => set(p.copyWith(autoTurnSeconds: v.round())),
          ),
        ],
      ),
    ];
  },
  profile,
  onChanged,
  title: 'Control options',
);

Future<void> showThemes(BuildContext context, ReadingProfile profile, ProfileChanged onChanged) => _sheet(
  context,
  (setSheet, get, set) {
    final p = get();
    final current = p.theme.id;
    return [
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.9,
        children: [
          for (final t in readerThemes)
            InkWell(
              key: Key('theme-${t.id}'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => set(p.withTheme(t)),
              child: Ink(
                decoration: BoxDecoration(
                  color: t.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: t.id == current ? Theme.of(context).colorScheme.primary : t.ink.withValues(alpha: 0.15),
                    width: t.id == current ? 2.5 : 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    t.name,
                    style: TextStyle(color: t.ink, fontFamily: 'serif', fontSize: 16),
                  ),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        'Day and night each remember their own theme; the day/night button switches between them.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const Divider(height: 24),
      _SavedSettings(current: get, onLoad: set),
    ];
  },
  profile,
  onChanged,
  title: 'Themes',
);

Future<void> _sheet(
  BuildContext context,
  List<Widget> Function(StateSetter setSheet, ReadingProfile Function() get, ProfileChanged set) build,
  ReadingProfile profile,
  ProfileChanged onChanged, {
  required String title,
}) {
  var current = profile;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheet) {
        void set(ReadingProfile p) {
          setSheet(() => current = p);
          onChanged(p);
        }

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              ...build(setSheet, () => current, set),
            ],
          ),
        );
      },
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group({required this.children, this.onReset});

  final List<Widget> children;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...children,
          if (onReset != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onReset,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset'),
              ),
            ),
        ],
      ),
    ),
  );
}

// Label · value · slider · − +, as in Moon Reader. The slider applies when released;
// − and + apply at once.
class _Stepper extends StatefulWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    this.format,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final String Function(double)? format;
  final ValueChanged<double> onChanged;

  @override
  State<_Stepper> createState() => _StepperState();
}

class _StepperState extends State<_Stepper> {
  double? _dragging;

  String _text(double v) => widget.format?.call(v) ?? v.round().toString();

  double _snap(double v) => ((v / widget.step).round() * widget.step).clamp(widget.min, widget.max).toDouble();

  @override
  Widget build(BuildContext context) {
    final v = _dragging ?? widget.value;
    return Row(
      key: Key('option-${widget.label}'),
      children: [
        SizedBox(width: 104, child: Text(widget.label, style: Theme.of(context).textTheme.bodyMedium)),
        SizedBox(width: 44, child: Text(_text(v), textAlign: TextAlign.end)),
        Expanded(
          child: Slider(
            value: v.clamp(widget.min, widget.max),
            min: widget.min,
            max: widget.max,
            divisions: ((widget.max - widget.min) / widget.step).round(),
            onChanged: (x) => setState(() => _dragging = _snap(x)),
            onChangeEnd: (x) {
              setState(() => _dragging = null);
              widget.onChanged(_snap(x));
            },
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Less',
          icon: const Icon(Icons.remove),
          onPressed: v <= widget.min ? null : () => widget.onChanged(_snap(v - widget.step)),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'More',
          icon: const Icon(Icons.add),
          onPressed: v >= widget.max ? null : () => widget.onChanged(_snap(v + widget.step)),
        ),
      ],
    );
  }
}


// Named sets of all reading settings (Moon Reader: save / load theme).
class _SavedSettings extends StatefulWidget {
  const _SavedSettings({required this.current, required this.onLoad});

  final ReadingProfile Function() current;
  final ProfileChanged onLoad;

  @override
  State<_SavedSettings> createState() => _SavedSettingsState();
}

class _SavedSettingsState extends State<_SavedSettings> {
  Map<String, ReadingProfile> _saved = const {};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final saved = await ReadingProfile.savedThemes();
      if (mounted) setState(() => _saved = saved);
    } catch (_) {
      // No storage available: nothing saved to show.
    }
  }

  Future<void> _saveAs() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Save current settings'),
        content: TextField(
          key: const Key('savedSettingsName'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(dialog, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(dialog, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await widget.current().saveTheme(name.trim());
    await _refresh();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(child: Text('Saved settings', style: Theme.of(context).textTheme.titleSmall)),
          TextButton.icon(
            key: const Key('saveSettings'),
            onPressed: _saveAs,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Save current'),
          ),
        ],
      ),
      if (_saved.isEmpty)
        Text('Font, spacing, margins, theme and controls are saved together under a name.',
            style: Theme.of(context).textTheme.bodySmall),
      for (final e in _saved.entries)
        ListTile(
          key: Key('saved-${e.key}'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(e.key),
          subtitle: Text('${e.value.theme.name} · size ${e.value.fontSize.toStringAsFixed(e.value.fontSize % 1 == 0 ? 0 : 1)}'),
          onTap: () => widget.onLoad(e.value.copyWith(nativeEngine: widget.current().nativeEngine)),
          trailing: IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () async {
              await ReadingProfile.deleteTheme(e.key);
              await _refresh();
            },
          ),
        ),
    ],
  );
}
