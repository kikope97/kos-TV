import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/current_app_localizations.dart';
import '../../widgets/kos_logo.dart';

/// Kos TV: what shows when startup itself fails, before the app is built (a
/// full disk, storage that can't be read). The kOS TV logo, what happened and
/// a Retry button, which the remote, a tap and a click can all reach. It
/// stands on its own: nothing of the app's services is there to lean on.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.onRetry});

  /// Runs startup again. The screen waits on it, and it replaces this one
  /// when it gets through.
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: KosBrand.violet,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // The language picked in the app when it can be read, the device's
      // otherwise.
      locale: currentAppLocale(
        WidgetsBinding.instance.platformDispatcher.locale,
      ),
      localeResolutionCallback: (locale, _) => resolveAppUiLocale(locale),
      home: StartupFailureScreen(onRetry: onRetry),
    );
  }
}

class StartupFailureScreen extends StatefulWidget {
  const StartupFailureScreen({super.key, required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  State<StartupFailureScreen> createState() => _StartupFailureScreenState();
}

class _StartupFailureScreenState extends State<StartupFailureScreen> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final logoHeight = (MediaQuery.sizeOf(context).shortestSide * 0.1).clamp(
      40.0,
      96.0,
    );
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  KosLogo(height: logoHeight),
                  const SizedBox(height: 32),
                  Text(
                    l10n.kostvStartupFailedTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: KosBrand.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.kostvStartupFailedMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFC9D2E6)),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    autofocus: true,
                    // Never disabled while it retries, so the remote's focus
                    // stays on it; [_retry] ignores the presses meanwhile.
                    onPressed: _retry,
                    child: _retrying
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.retry),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
