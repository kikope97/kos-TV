import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../l10n/app_localizations.dart';
import '../navigation/destinations.dart';
import '../widgets/focus/request_initial_focus.dart';
import '../widgets/kos_logo.dart';

/// Kos TV: an address the app has no page for (an old bookmark, a link typed
/// wrong on the web, a page since taken out). It says so and offers the way
/// to Home, which the remote lands on, and a tap or a click reaches. It
/// stands in for go_router's own page, which was in English.
class RouteNotFoundScreen extends StatelessWidget {
  const RouteNotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    final logoHeight = (MediaQuery.sizeOf(context).shortestSide * 0.08).clamp(
      36.0,
      72.0,
    );
    return Scaffold(
      backgroundColor: AppColorScheme.background,
      body: SafeArea(
        child: RequestInitialFocus(
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
                      l10n.kostvPageNotFoundTitle,
                      textAlign: TextAlign.center,
                      style: textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.kostvPageNotFoundMessage,
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppColorScheme.onBackground.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      autofocus: true,
                      onPressed: () => context.go(Destinations.home),
                      icon: const Icon(Icons.home_rounded),
                      label: Text(l10n.kostvGoToHome),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
