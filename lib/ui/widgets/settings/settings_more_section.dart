import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../l10n/app_localizations.dart';
import '../../../util/focus/dpad_keys.dart';
import 'preference_tiles.dart';
import 'settings_preview_scope.dart';

/// Kos TV: which «Más ajustes» folds are open while Settings is open.
///
/// Settings come in two levels: what the family may want to touch shows on
/// each screen, and the technical rest waits in a fold at its end. The panel
/// keeps one of these for as long as it is open, so a fold stays open when a
/// screen inside it is opened and closed again (and Back can hand the focus
/// back to the row that opened it), and every visit to Settings starts with
/// them all closed.
class SettingsMoreController extends ChangeNotifier {
  final Set<String> _open = {};
  final Set<String> _closed = {};
  bool _allOpen = false;

  bool isOpen(String id) =>
      _allOpen ? !_closed.contains(id) : _open.contains(id);

  void setOpen(String id, bool open) {
    if (isOpen(id) == open) return;
    if (open) {
      _open.add(id);
      _closed.remove(id);
    } else {
      _open.remove(id);
      _closed.add(id);
    }
    notifyListeners();
  }

  void toggle(String id) => setOpen(id, !isOpen(id));

  /// Opens every fold, for a setting reached from the search: wherever it
  /// sits, it shows, and so does the row that leads to it from the screen
  /// above. A fold closed by hand afterwards stays closed.
  void openAll() {
    if (_allOpen && _closed.isEmpty) return;
    _allOpen = true;
    _closed.clear();
    notifyListeners();
  }
}

/// Hands the panel's [SettingsMoreController] to the settings screens.
///
/// A screen built without one (on its own, as in a test) shows its advanced
/// settings straight away, with no fold, as it did before.
class SettingsMoreScope extends InheritedNotifier<SettingsMoreController> {
  const SettingsMoreScope({
    super.key,
    required SettingsMoreController controller,
    required super.child,
  }) : super(notifier: controller);

  static SettingsMoreController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsMoreScope>()?.notifier;
}

/// The end of a settings screen: the «Más ajustes» row and, below it while
/// open, [children] (headers and sections, as anywhere else on the screen).
/// Spread it into the screen's list, so each piece stays a child of the list
/// itself and the preview inspector still finds the header above a setting.
///
/// [id] names the fold (the search opens it by this name), [summary] says in
/// a few words what is inside. Nothing is drawn when [children] is empty.
List<Widget> settingsMore(
  BuildContext context, {
  required String id,
  required String summary,
  required List<Widget> children,
}) {
  if (children.isEmpty) return const [];
  final controller = SettingsMoreScope.maybeOf(context);
  if (controller == null) return children;
  final open = controller.isOpen(id);
  return [
    SettingsMoreTile(
      key: ValueKey('settings-more-$id'),
      open: open,
      summary: summary,
      onToggle: () => controller.toggle(id),
    ),
    if (open) ...children,
  ];
}

/// The «Más ajustes» row: opens and closes the advanced settings below it.
/// The focus stays on it either way, and opening it scrolls the list so the
/// first of them shows (a touch screen doesn't scroll on its own).
class SettingsMoreTile extends StatelessWidget {
  const SettingsMoreTile({
    super.key,
    required this.open,
    required this.summary,
    required this.onToggle,
  });

  final bool open;
  final String summary;
  final VoidCallback onToggle;

  void _toggle(BuildContext context) {
    final opening = !open;
    onToggle();
    if (!opening) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        alignment: 0.15,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = open ? l10n.kostvFewerSettings : l10n.kostvMoreSettings;
    return SettingsPreviewReporter(
      describe: () => SettingsPreviewEntry(title: title, description: summary),
      // OK on the remote toggles it, as on the other settings rows.
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, event) {
          if (!event.logicalKey.isSelectKey) return KeyEventResult.ignored;
          if (event is KeyDownEvent) _toggle(context);
          return KeyEventResult.handled;
        },
        child: TvFocusHighlight(
          builder: (context, focused) {
            final highlighted = focused && settingsTileInvertsOnFocus;
            final muted = highlighted
                ? AppColors.black.withValues(alpha: 0.54)
                : AppColorScheme.onSurface.withValues(alpha: 0.7);
            return ListTile(
              focusColor: Colors.transparent,
              hoverColor: Colors.transparent,
              leading: buildSettingsLeadingIconShell(
                context,
                icon: const Icon(Icons.tune_rounded),
                focused: focused,
                iconColor: highlighted
                    ? AppColors.black.withValues(alpha: 0.54)
                    : AppColorScheme.onSurface.withValues(alpha: 0.78),
              ),
              title: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: highlighted
                      ? AppColors.black.withValues(alpha: 0.87)
                      : settingsHeadlineColor(),
                ),
              ),
              subtitle: open
                  ? null
                  : Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
              trailing: AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(Icons.expand_more_rounded, size: 22, color: muted),
              ),
              onTap: () => _toggle(context),
            );
          },
        ),
      ),
    );
  }
}
