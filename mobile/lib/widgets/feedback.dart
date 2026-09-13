import 'package:flutter/material.dart';

import '../api/api_exception.dart';
import '../theme.dart';

/// Shows a failed API call. The backend owns the wording, so the two sides
/// can't disagree about what went wrong.
void showApiError(BuildContext context, Object error) {
  final message = switch (error) {
    ApiException e => e.message,
    // A plain string is a validation message the screen wrote itself.
    String message => message,
    _ => 'Algo deu errado. Tente novamente.',
  };

  _snack(context, message, MtColors.danger);
}

void showSuccess(BuildContext context, String message) {
  _snack(context, message, MtColors.petrol);
}

void _snack(BuildContext context, String message, Color background) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

/// Centred spinner for a screen that is loading its first data.
class MtLoading extends StatelessWidget {
  const MtLoading({super.key});

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: CircularProgressIndicator(strokeWidth: 2.5),
    ),
  );
}

/// Empty/error state with an optional retry, used by the list screens.
class MtEmptyState extends StatelessWidget {
  const MtEmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.onRetry,
  });

  final String message;
  final IconData icon;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 34, color: MtColors.slate500),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: MtColors.slate500,
                height: 1.5,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: onRetry,
                child: const Text('Tentar de novo'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
