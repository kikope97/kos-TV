import 'package:flutter/material.dart';
import 'package:server_core/server_core.dart';

import '../../../../l10n/app_localizations.dart';
import '../../../widgets/adaptive/adaptive_dialog.dart';

/// Plugins from the official repository install without asking.
const _trustedRepoUrl = 'https://repo.jellyfin.org/';

/// Asks before installing [version] from any other repository. True means
/// go ahead.
Future<bool> confirmPluginInstall(
  BuildContext context,
  VersionInfo version,
) async {
  if (version.repositoryUrl.startsWith(_trustedRepoUrl)) return true;
  final l10n = AppLocalizations.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(l10n.adminPluginInstallConfirmTitle),
      content: Text(l10n.adminPluginInstallDisclaimer),
      actions: [
        adaptiveDialogAction(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.install),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Kos TV: the server plugin every kOS TV app relies on (the same id as the
/// official one it is a copy of).
const kosTvPluginId = '561f86df-fa00-4fca-aa4d-2fed0e332670';

/// Jellyfin may send a plugin id with or without dashes.
bool isKosTvPlugin(PluginInfo plugin) =>
    plugin.id.replaceAll('-', '').toLowerCase() ==
    kosTvPluginId.replaceAll('-', '');

/// Asks before turning [plugin] off or uninstalling it ([uninstall]). For the
/// kOS TV plugin it also says that every app in the house depends on it. True
/// means go ahead.
Future<bool> confirmPluginRemoval(
  BuildContext context,
  PluginInfo plugin, {
  required bool uninstall,
}) async {
  final l10n = AppLocalizations.of(context);
  final question = uninstall
      ? l10n.adminUninstallPluginConfirm(plugin.name)
      : l10n.adminDisablePluginConfirm(plugin.name);
  final kosTv = isKosTvPlugin(plugin);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(
        uninstall ? l10n.adminUninstallPlugin : l10n.adminDisablePluginTitle,
      ),
      content: Text(
        kosTv ? '$question\n\n${l10n.adminKosTvPluginWarning}' : question,
      ),
      actions: [
        adaptiveDialogAction(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
            foregroundColor: Theme.of(ctx).colorScheme.onError,
          ),
          child: Text(uninstall ? l10n.uninstall : l10n.disable),
        ),
      ],
    ),
  );
  return confirmed == true;
}
