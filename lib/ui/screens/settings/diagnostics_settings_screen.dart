import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';
import 'package:server_core/server_core.dart';

import '../../../data/services/log_service.dart';
import '../../../data/services/media_server_client_factory.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/artwork_timing.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/overlay_sheet.dart';
import '../../widgets/settings/clean_settings_typography.dart';
import '../../widgets/settings/preference_tiles.dart';
import '../../../l10n/app_localizations.dart';
import '../../util/error_message.dart';
import 'settings_app_bar.dart';

class DiagnosticsSettingsScreen extends StatefulWidget {
  const DiagnosticsSettingsScreen({super.key});

  @override
  State<DiagnosticsSettingsScreen> createState() =>
      _DiagnosticsSettingsScreenState();
}

class _DiagnosticsSettingsScreenState extends State<DiagnosticsSettingsScreen> {
  LogService get _log => GetIt.instance<LogService>();

  bool _uploading = false;
  LogCategory? _filter;

  Future<void> _sendReport() async {
    setState(() => _uploading = true);
    ArtworkTimings.prepareReport();
    try {
      final fileName = await _log.uploadToServer();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      _showSnack(
        fileName == null
            ? l10n.kostvReportSent
            : l10n.kostvReportSentAs(fileName),
      );
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      _showSnack(l10n.kostvReportSendFailed(describeError(e, l10n)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _copyAll() async {
    ArtworkTimings.prepareReport();
    await Clipboard.setData(ClipboardData(text: _log.exportText()));
    if (!mounted) return;
    _showSnack(AppLocalizations.of(context).kostvLogsCopied);
  }

  Future<void> _copyEntry(LogEntry entry) async {
    await Clipboard.setData(ClipboardData(text: entry.format()));
    if (!mounted) return;
    _showSnack(AppLocalizations.of(context).kostvLogEntryCopied);
  }

  void _clearLogs() {
    _log.clear();
    _showSnack(AppLocalizations.of(context).kostvLogsCleared);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _supportsUpload => _log.canUploadToServer;

  Future<void> _pickFilter() async {
    final l10n = AppLocalizations.of(context);
    final selected = await showFocusRestoringModalBottomSheet<_FilterChoice>(
      context: context,
      builder: (ctx) => SafeArea(
        child: RadioGroup<LogCategory?>(
          groupValue: _filter,
          onChanged: (value) => Navigator.pop(ctx, _FilterChoice(value)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<LogCategory?>(
                title: Text(l10n.kostvAllCategories),
                value: null,
              ),
              for (final category in LogCategory.values)
                RadioListTile<LogCategory?>(
                  title: Text(_categoryLabel(category, l10n)),
                  value: category,
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _filter = selected.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RequestInitialFocus(
      child: withCleanSettingsTypography(
        context,
        Scaffold(
          appBar: buildSettingsAppBar(
            context,
            Text(AppLocalizations.of(context).kostvDiagnostics),
          ),
          body: AnimatedBuilder(
            animation: _log,
            builder: (context, _) => _buildBody(context),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final enabled = _log.isEnabled;
    final count = _log.entryCount;
    final hasEntries = count > 0;

    final entries = _log.entries
        .where((e) => _filter == null || e.category == _filter)
        .toList()
        .reversed
        .toList();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Section(title: l10n.kostvLogging),
              SwitchPreferenceTile(
                preference: UserPreferences.diagnosticLoggingEnabled,
                title: l10n.kostvDiagnosticLogging,
                subtitle: l10n.kostvDiagnosticLoggingSubtitle,
                icon: Icons.bug_report,
              ),
              SwitchPreferenceTile(
                preference: UserPreferences.crashReportsEnabled,
                title: l10n.kostvSendCrashReports,
                subtitle: l10n.kostvSendCrashReportsSubtitle,
                icon: Icons.report_outlined,
              ),
              _Section(
                title: enabled
                    ? l10n.kostvReportsCaptured(count)
                    : l10n.kostvReports,
              ),
              _ActionTile(
                icon: Icons.cloud_upload,
                title: l10n.kostvSendReport,
                subtitle: _sendSubtitle(enabled, l10n),
                enabled:
                    enabled && hasEntries && _supportsUpload && !_uploading,
                trailing: _uploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
                onTap: _sendReport,
              ),
              _ActionTile(
                icon: Icons.copy_all,
                title: l10n.kostvCopyAllLogs,
                subtitle: l10n.kostvCopyAllLogsSubtitle,
                enabled: hasEntries,
                onTap: _copyAll,
              ),
              _ActionTile(
                icon: Icons.delete_outline,
                title: l10n.kostvClearLogs,
                subtitle: l10n.kostvClearLogsSubtitle,
                enabled: hasEntries,
                destructive: true,
                onTap: _clearLogs,
              ),
              _Section(
                title: _filter == null
                    ? l10n.kostvRecentLogs
                    : l10n.kostvRecentLogsFiltered(entries.length, count),
              ),
              _ActionTile(
                icon: Icons.filter_list,
                title: l10n.musicFilter,
                subtitle: _filter == null
                    ? l10n.kostvAllCategories
                    : _categoryLabel(_filter!, l10n),
                enabled: enabled || hasEntries,
                trailing: const Icon(Icons.expand_more, size: 20),
                onTap: _pickFilter,
              ),
            ],
          ),
        ),
        if (entries.isEmpty)
          SliverToBoxAdapter(child: _buildEmptyState(enabled, l10n))
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _LogTile(
                entry: entries[index],
                onTap: () => _copyEntry(entries[index]),
              ),
              childCount: entries.length,
            ),
          ),
        SliverToBoxAdapter(
          child: SizedBox(height: 24 + MediaQuery.paddingOf(context).bottom),
        ),
      ],
    );
  }

  String _sendSubtitle(bool enabled, AppLocalizations l10n) {
    if (!enabled) return l10n.kostvTurnOnLoggingFirst;
    if (!_supportsUpload) return _uploadUnavailableReason(l10n);
    if (_log.entryCount == 0) return l10n.kostvNoLogEntriesCaptured;
    return l10n.kostvSendReportSubtitle;
  }

  /// [LogService.uploadUnavailableReason], in the app's language.
  static String _uploadUnavailableReason(AppLocalizations l10n) {
    final MediaServerClient client;
    try {
      client = GetIt.instance<MediaServerClientFactory>().getActiveClient();
    } on StateError {
      return l10n.kostvReportNeedsSignIn;
    }
    return client.serverType == ServerType.silo
        ? l10n.kostvReportNeedsPlugin
        : l10n.kostvReportNotSupported;
  }

  Widget _buildEmptyState(bool enabled, AppLocalizations l10n) {
    final total = _log.entryCount;
    final filtered = _filter != null && total > 0;

    final IconData icon;
    final String message;
    if (filtered) {
      icon = Icons.filter_list_off;
      message = l10n.kostvNoLogEntriesInCategory(
        total,
        _categoryLabel(_filter!, l10n),
      );
    } else if (enabled) {
      icon = Icons.hourglass_empty;
      message = l10n.kostvNoLogEntriesYet;
    } else {
      icon = Icons.toggle_off_outlined;
      message = l10n.kostvLoggingOff;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: Column(
        children: [
          Icon(
            icon,
            size: 40,
            color: AppColorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  static String _categoryLabel(
    LogCategory category,
    AppLocalizations l10n,
  ) => switch (category) {
    LogCategory.general => l10n.general,
    LogCategory.media => l10n.kostvLogCategoryMedia,
    LogCategory.network => l10n.network,
    LogCategory.auth => l10n.authentication,
    LogCategory.playback => l10n.playback,
    LogCategory.sync => l10n.kostvLogCategorySync,
    LogCategory.artwork => l10n.kostvLogCategoryArtwork,
  };
}

class _FilterChoice {
  const _FilterChoice(this.value);
  final LogCategory? value;
}

class _Section extends StatelessWidget {
  const _Section({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColorScheme.accent,
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.enabled = true,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool enabled;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final accent = destructive
        ? AppColorScheme.statusRequested
        : AppColorScheme.accent;

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (!event.logicalKey.isSelectKey) return KeyEventResult.ignored;
        if (event is KeyDownEvent && enabled) onTap();
        return KeyEventResult.handled;
      },
      child: TvFocusHighlight(
        builder: (context, focused) {
          final foreground = !enabled
              ? AppColorScheme.onSurface.withValues(alpha: 0.38)
              : focused
              ? AppColors.black.withValues(alpha: 0.87)
              : (destructive ? accent : AppColorScheme.onSurface);
          final iconColor = !enabled
              ? AppColorScheme.onSurface.withValues(alpha: 0.38)
              : focused
              ? AppColors.black.withValues(alpha: 0.7)
              : accent;

          return ListTile(
            enabled: enabled,
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            leading: Icon(icon, color: iconColor),
            title: Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
            subtitle: Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: foreground.withValues(alpha: 0.7),
              ),
            ),
            trailing: trailing,
            onTap: enabled ? onTap : null,
          );
        },
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry, required this.onTap});

  final LogEntry entry;
  final VoidCallback onTap;

  Color _levelColor() => switch (entry.level) {
    LogLevel.error => AppColorScheme.statusRequested,
    LogLevel.warning => AppColorScheme.statusPending,
    LogLevel.info => AppColorScheme.statusAvailable,
    LogLevel.debug => AppColorScheme.onSurface.withValues(alpha: 0.6),
  };

  @override
  Widget build(BuildContext context) {
    final time = entry.time;
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    final ss = time.second.toString().padLeft(2, '0');
    final levelColor = _levelColor();

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (!event.logicalKey.isSelectKey) return KeyEventResult.ignored;
        if (event is KeyDownEvent) onTap();
        return KeyEventResult.handled;
      },
      child: TvFocusHighlight(
        builder: (context, focused) {
          final textColor = focused
              ? AppColors.black.withValues(alpha: 0.87)
              : AppColorScheme.onSurface;
          return ListTile(
            dense: true,
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            onTap: onTap,
            leading: Container(
              width: 4,
              height: 40,
              decoration: BoxDecoration(
                color: levelColor,
                borderRadius: AppRadius.circular(2),
              ),
            ),
            title: Text(
              '$hh:$mm:$ss  ${entry.level.label}  ${entry.category.label}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: focused
                    ? AppColors.black.withValues(alpha: 0.7)
                    : levelColor,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.message,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: textColor,
                  ),
                ),
                if (entry.error != null)
                  Text(
                    entry.error!,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: focused
                          ? AppColors.black.withValues(alpha: 0.7)
                          : AppColorScheme.statusRequested,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
