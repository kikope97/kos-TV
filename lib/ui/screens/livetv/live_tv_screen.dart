import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../l10n/app_localizations.dart';
import '../../../preference/preference_constants.dart';
import '../../../util/focus/key_event_utils.dart';
import '../../../util/platform_detection.dart';
import '../../navigation/destinations.dart';
import '../../widgets/bottom_nav/bottom_navbar.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/navigation_layout.dart';
import '../../widgets/top_toolbar.dart';
import '../detail/kostv/kostv_detail_buttons.dart'
    show kostvLight, kostvOnLight;

class LiveTvScreen extends StatelessWidget {
  const LiveTvScreen({super.key});

  // TV leaves on the remote's Back and the app never opens this page there, so
  // only the other layouts get the navbar.
  static bool get _showNavbar => !PlatformDetection.isTV;

  @override
  Widget build(BuildContext context) {
    final page = _buildContent(context);
    return RequestInitialFocus(
      child: _showNavbar
          ? Scaffold(
              backgroundColor: Colors.black,
              body: NavigationLayout(showBackButton: true, child: page),
            )
          : page,
    );
  }

  Widget _buildContent(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // The navbar draws over the page, and a left or bottom one puts the back
    // button in the corner the title uses.
    final position =
        NavigationLayout.positionNotifier.value ?? NavbarPosition.top;
    final topInset = !_showNavbar
        ? 0.0
        : position == NavbarPosition.top
        ? TopToolbar.heightFor(context)
        : 56.0;
    final leftInset = _showNavbar && position == NavbarPosition.left
        ? 72.0
        : 0.0;
    final items = <({IconData icon, String title, VoidCallback onTap})>[
      (
        icon: Icons.tv,
        title: l10n.guide,
        onTap: () => context.push(Destinations.liveTvGuide),
      ),
      (
        icon: Icons.fiber_dvr,
        title: l10n.recordings,
        onTap: () => context.push(Destinations.liveTvRecordings),
      ),
      (
        icon: Icons.schedule,
        title: l10n.schedule,
        onTap: () => context.push(Destinations.liveTvSchedule),
      ),
      (
        icon: Icons.repeat,
        title: l10n.seriesRecordings,
        onTap: () => context.push(Destinations.liveTvSeriesRecordings),
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              // Kos TV: the app's dark greys, not the theme's blue.
              const Color(0xFF0B0C10),
              const Color(0xFF14161C),
              const Color(0xFF1C1F27),
            ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final columns = width >= 1100 ? 2 : 1;
              final childAspectRatio = columns == 2 ? 2.8 : 3.6;

              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1240),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      32 + leftInset,
                      28 + topInset,
                      32,
                      bottomNavContentPadding(context, 32),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.liveTv,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          l10n.guide,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(color: Colors.white70),
                        ),
                        const SizedBox(height: 28),
                        Expanded(
                          child: GridView.builder(
                            itemCount: items.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 20,
                                  mainAxisSpacing: 20,
                                  childAspectRatio: childAspectRatio,
                                ),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return _LiveTvMenuCard(
                                icon: item.icon,
                                title: item.title,
                                autofocus: index == 0,
                                onTap: item.onTap,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LiveTvMenuCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final bool autofocus;
  final VoidCallback onTap;

  const _LiveTvMenuCard({
    required this.icon,
    required this.title,
    required this.autofocus,
    required this.onTap,
  });

  @override
  State<_LiveTvMenuCard> createState() => _LiveTvMenuCardState();
}

class _LiveTvMenuCardState extends State<_LiveTvMenuCard> {
  bool _focused = false;
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    return handleOneShotSelect(event, widget.onTap);
  }

  @override
  Widget build(BuildContext context) {
    // Kos TV: focus lifts the card and turns it white, as buttons do.
    final borderColor = _focused
        ? Colors.transparent
        : Colors.white.withValues(alpha: 0.12);
    final shadowColor = Colors.black.withValues(
      alpha: _focused ? 0.5 : 0.16,
    );
    final ink = _focused ? kostvOnLight : Colors.white;

    return Focus(
      autofocus: widget.autofocus,
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      onFocusChange: (focused) {
        if (_focused != focused) {
          setState(() => _focused = focused);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          transform: Matrix4.identity()
            ..scaleByDouble(_focused ? 1.02 : 1.0, _focused ? 1.02 : 1.0, 1.0, 1.0),
          decoration: BoxDecoration(
            color: _focused ? kostvLight : const Color(0xCC1A1C22),
            borderRadius: AppRadius.circular(24),
            border: Border.all(color: borderColor, width: _focused ? 2.4 : 1),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: _focused ? 28 : 16,
                spreadRadius: _focused ? 2 : 0,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: (_focused ? kostvOnLight : Colors.white).withValues(
                      alpha: 0.1,
                    ),
                    borderRadius: AppRadius.circular(20),
                  ),
                  child: Icon(widget.icon, color: ink, size: 34),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward,
                  color: _focused ? ink : Colors.white.withValues(alpha: 0.55),
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
