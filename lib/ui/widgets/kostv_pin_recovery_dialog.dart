import 'package:custom_tv_text_field/custom_tv_text_field.dart';
import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../l10n/app_localizations.dart';
import '../screens/auth/silo_secret_field.dart';
import 'overlay_sheet.dart';

/// Kos TV: the way out of a PIN kept on the device that was forgotten: the
/// Jellyfin password of the account it belongs to, which the server checks.
///
/// [onSubmit] checks the typed password and does what the PIN would have
/// let through, answering null when it did, or what to say when it didn't
/// (the dialog stays open for another go).
class KostvPinRecoveryDialog extends StatefulWidget {
  const KostvPinRecoveryDialog({
    super.key,
    required this.username,
    required this.leavesKidsMode,
    required this.onSubmit,
  });

  final String username;

  /// Whether getting through also leaves Kids Mode, which the message says.
  final bool leavesKidsMode;
  final Future<String?> Function(String password) onSubmit;

  /// Shows the dialog. True once [onSubmit] went through.
  static Future<bool> show(
    BuildContext context, {
    required String username,
    required bool leavesKidsMode,
    required Future<String?> Function(String password) onSubmit,
  }) async {
    final result = await showFocusRestoringDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => KostvPinRecoveryDialog(
        username: username,
        leavesKidsMode: leavesKidsMode,
        onSubmit: onSubmit,
      ),
    );
    return result ?? false;
  }

  @override
  State<KostvPinRecoveryDialog> createState() => _KostvPinRecoveryDialogState();
}

class _KostvPinRecoveryDialogState extends State<KostvPinRecoveryDialog> {
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode(debugLabel: 'PinRecoveryPassword');
  final _submitFocus = FocusNode(debugLabel: 'PinRecoverySubmit');
  final _passwordTvKey = GlobalKey<CustomTVTextFieldState>();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _passwordFocus.dispose();
    _submitFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.onSubmit(_passwordController.text);
    } catch (_) {
      if (!mounted) return;
      error = AppLocalizations.of(context).kostvPinRecoveryNeedsServer;
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }
    _passwordController.clear();
    setState(() {
      _busy = false;
      _error = error;
    });
    // The button went dead while the server was asked, which takes the
    // remote's focus with it: back to the password for another go.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _passwordFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final insets = MediaQuery.of(context).viewInsets;
    final onSurface = AppColorScheme.onSurface;

    return PopScope(
      // Not while the server is being asked: what it answers still has to
      // be carried out.
      canPop: !_busy,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.only(bottom: insets.bottom),
          child: SingleChildScrollView(
            child: Container(
              constraints: const BoxConstraints(minWidth: 320, maxWidth: 440),
              decoration: BoxDecoration(
                color: AppColorScheme.surface.withValues(alpha: 0.9),
                borderRadius: AppRadius.circular(20),
                border: Border.fromBorderSide(
                  ThemeRegistry.active.borders.chipBorder,
                ),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.pinForgot,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.leavesKidsMode
                        ? l10n.kostvPinRecoveryKidsMessage
                        : l10n.kostvPinRecoveryMessage,
                    style: TextStyle(color: onSurface.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.kostvPinRecoveryUser(widget.username),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SiloSecretField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    tvKey: _passwordTvKey,
                    label: l10n.password,
                    autofocus: true,
                    enabled: !_busy,
                    autofillHints: const [AutofillHints.password],
                    down: _submitFocus,
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.kostvPinRecoveryEmptyHint,
                    style: TextStyle(
                      fontSize: 13,
                      color: onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: AppColorScheme.statusRequested),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: Text(
                          l10n.cancel,
                          style: TextStyle(
                            color: onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        focusNode: _submitFocus,
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(l10n.kostvPinRecoveryConfirm),
                      ),
                    ],
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
