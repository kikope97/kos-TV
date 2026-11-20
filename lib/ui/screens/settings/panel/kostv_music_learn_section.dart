part of '../settings_side_panel.dart';

/// Kos TV: Music's own settings, in Playback: whether the server plugin
/// learns from what the person listens to (their daily mixes, the mix of
/// the time of day and the weekly discovery come from it), how much it has
/// kept since when, and a way to delete it all. The setting is the
/// person's, kept on the server, so it follows them to every device.
///
/// Shown only when the plugin has the route: with an older one (or none),
/// nothing is shown. When the plugin couldn't be asked (no network, a slow
/// or failing server), it is said, with a way to ask again: the setting
/// doesn't go away for that.
/// Public for its tests.
class KostvMusicLearnSection extends StatefulWidget {
  const KostvMusicLearnSection({super.key});

  @override
  State<KostvMusicLearnSection> createState() => _KostvMusicLearnSectionState();
}

class _KostvMusicLearnSectionState extends State<KostvMusicLearnSection> {
  KostvMusicLearnState? _state;
  bool _busy = false;

  /// Kos TV: the plugin didn't answer the last time it was asked (and
  /// nothing of it is known yet).
  bool _unanswered = false;

  MediaServerClient? get _client =>
      GetIt.instance.isRegistered<MediaServerClient>()
      ? GetIt.instance<MediaServerClient>()
      : null;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  /// Who the section is for: an answer that lands after a switch of person
  /// (the same client, another session) isn't theirs.
  ({String? user, String? token}) _whoOf(MediaServerClient client) =>
      (user: client.userId, token: client.accessToken);

  Future<void> _read() async {
    final client = _client;
    if (client == null) return;
    final who = _whoOf(client);
    if (_unanswered) setState(() => _busy = true);
    final answer = await KostvMusicPlugin.instance.settings(client);
    if (!mounted || _whoOf(client) != who) return;
    setState(() {
      _busy = false;
      if (answer.failed) {
        // What was known stays; with nothing known, it says so.
        _unanswered = _state == null;
        return;
      }
      _unanswered = false;
      _state = answer.value;
    });
  }

  void _say(String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setLearn(bool learn) async {
    final client = _client;
    final before = _state;
    if (client == null || before == null || _busy) return;
    final who = _whoOf(client);
    final l10n = AppLocalizations.of(context);
    // Shown at once; put back if the server didn't take it.
    setState(() {
      _busy = true;
      _state = KostvMusicLearnState(
        learn: learn,
        listens: before.listens,
        since: before.since,
      );
    });
    final after = await KostvMusicPlugin.instance.setLearn(client, learn);
    if (!mounted) return;
    if (_whoOf(client) != who) {
      setState(() => _busy = false);
      return;
    }
    setState(() {
      _busy = false;
      _state = after ?? before;
    });
    if (after == null) _say(l10n.kostvMusicCantChange);
  }

  Future<void> _forget() async {
    final client = _client;
    if (client == null || _busy) return;
    final l10n = AppLocalizations.of(context);
    final confirmed = await showFocusRestoringDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: Text(l10n.kostvMusicLearnForgetTitle),
        content: Text(l10n.kostvMusicLearnForgetBody),
        actions: [
          adaptiveDialogAction(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          adaptiveDialogAction(
            isDestructive: true,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.kostvMusicLearnForgetConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final who = _whoOf(client);
    setState(() => _busy = true);
    final done = await KostvMusicPlugin.instance.forgetListens(client);
    if (!mounted) return;
    setState(() => _busy = false);
    if (_whoOf(client) != who) return;
    if (!done) {
      _say(l10n.kostvMusicCantChange);
      return;
    }
    _say(l10n.kostvMusicLearnForgotten);
    // Nothing kept now, whatever the next read says (or if it fails).
    final before = _state;
    if (before != null) {
      setState(() => _state = KostvMusicLearnState(learn: before.learn));
    }
    await _read();
  }

  /// How much is kept: «1234 escuchas guardadas desde el 2 sept 2026».
  String _kept(AppLocalizations l10n, KostvMusicLearnState state) {
    final since = state.since;
    if (state.listens <= 0) return l10n.kostvMusicLearnNone;
    // The plugin may not say since when.
    if (since == null) return l10n.kostvMusicLearnCountNoDate(state.listens);
    final locale = Localizations.localeOf(context).toString();
    return l10n.kostvMusicLearnCount(
      state.listens,
      DateFormat.yMMMd(locale).format(since),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final l10n = AppLocalizations.of(context);
    if (state == null) {
      if (!_unanswered) return const SizedBox.shrink();
      // Kos TV: it couldn't be asked: said, with a way to ask again.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(l10n.kostvMusic),
          adaptiveListSection(
            children: [
              _TvSettingsListTile(
                leading: const Icon(Icons.auto_awesome_rounded),
                title: Text(l10n.kostvMusicLearn),
                subtitle: Text(l10n.kostvMusicLearnUnanswered),
                trailing: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                onTap: () {
                  if (!_busy) unawaited(_read());
                },
              ),
            ],
          ),
        ],
      );
    }
    final learnSubtitle = [
      state.learn ? l10n.kostvMusicLearnOn : l10n.kostvMusicLearnOff,
      _kept(l10n, state),
    ].join('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(l10n.kostvMusic),
        adaptiveListSection(
          children: [
            // Kos TV: the preview under the settings says what this is, as
            // it does for the other settings.
            SettingsPreviewReporter(
              describe: () => SettingsPreviewEntry(
                title: l10n.kostvMusicLearn,
                description: learnSubtitle,
              ),
              child: TvFocusHighlight(
                builder: (context, focused) {
                  final iconColor = focused && settingsTileInvertsOnFocus
                      ? AppColors.black.withValues(alpha: 0.54)
                      : (Theme.of(context).iconTheme.color ??
                            AppColorScheme.onSurface);
                  return SwitchListTile.adaptive(
                    secondary: buildSettingsLeadingIconShell(
                      context,
                      icon: const Icon(Icons.auto_awesome_rounded),
                      focused: focused,
                      iconColor: iconColor,
                    ),
                    title: Text(
                      l10n.kostvMusicLearn,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      learnSubtitle,
                      style: const TextStyle(fontSize: 12),
                    ),
                    isThreeLine: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    value: state.learn,
                    // Kos TV: never null while the server answers: a switch
                    // without it can't keep the focus, and the remote's would
                    // jump away. A press meanwhile is ignored (_setLearn).
                    onChanged: (value) => unawaited(_setLearn(value)),
                  );
                },
              ),
            ),
            _TvSettingsListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: Text(l10n.kostvMusicLearnForget),
              subtitle: Text(l10n.kostvMusicLearnForgetSubtitle),
              trailing: const SizedBox.shrink(),
              onTap: _busy ? null : () => unawaited(_forget()),
            ),
          ],
        ),
      ],
    );
  }
}
