import 'package:flutter/material.dart';

/// A never-blank error/empty state, per spec:
/// - source unavailable -> "showing the latest verified information"
/// - PDF failure -> "try official source"
class ErrorStateView extends StatelessWidget {
  final String message;
  final IconData icon;
  final VoidCallback? onRetry;

  const ErrorStateView({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.onRetry,
  });

  factory ErrorStateView.sourceUnavailable({VoidCallback? onRetry}) => ErrorStateView(
        message: 'The official source is temporarily unavailable. Showing the latest verified information.',
        icon: Icons.cloud_off,
        onRetry: onRetry,
      );

  /// For content with no bundled offline fallback (live announcements,
  /// documents) — unlike [sourceUnavailable], there is no cached data being
  /// shown here, so the copy doesn't claim there is.
  factory ErrorStateView.liveDataUnavailable({VoidCallback? onRetry}) => ErrorStateView(
        message: 'Unable to load live updates right now. Check your connection and try again.',
        icon: Icons.cloud_off,
        onRetry: onRetry,
      );

  factory ErrorStateView.pdfFailed({VoidCallback? onRetry}) => ErrorStateView(
        message: 'Unable to open document. Try the official source instead.',
        icon: Icons.picture_as_pdf_outlined,
        onRetry: onRetry,
      );

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: Colors.black45),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
