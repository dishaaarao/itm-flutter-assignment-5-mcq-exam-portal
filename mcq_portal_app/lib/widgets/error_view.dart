import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// Failure state with an actionable retry.
///
/// The message shown is the server's own where one exists — for a backend that
/// is simply not running, [ApiException] already produces the "make sure the
/// backend is running" text, which is the single most useful thing to say.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry, this.icon});

  final String message;
  final VoidCallback? onRetry;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? Icons.error_outline, size: 52, color: AppTheme.danger),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Color(0xFF475467), height: 1.4),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 22),
              SizedBox(
                width: 180,
                child: FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Try again'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
