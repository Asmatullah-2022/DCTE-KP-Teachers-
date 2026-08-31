import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/app_theme.dart';

/// Every official document/curriculum item must show: Official Source,
/// DCTE/KPESE, original URL, and published date if available.
class SourceAttribution extends StatelessWidget {
  final String department; // 'DCTE' | 'KPESE'
  final String sourceUrl;
  final DateTime? publishedDate;
  final int? sourcePage;

  const SourceAttribution({
    super.key,
    required this.department,
    required this.sourceUrl,
    this.publishedDate,
    this.sourcePage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryGreen.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryGreen.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_outlined, size: 16, color: AppTheme.primaryGreenDark),
              const SizedBox(width: 6),
              Text('Official Source', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Department: $department', style: Theme.of(context).textTheme.bodyMedium),
          if (publishedDate != null)
            Text('Published: ${DateFormat('MMM d, y').format(publishedDate!)}', style: Theme.of(context).textTheme.bodyMedium),
          if (sourcePage != null)
            Text('Source page: $sourcePage', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => launchUrl(Uri.parse(sourceUrl), mode: LaunchMode.externalApplication),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  sourceUrl.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf_outlined : Icons.open_in_new,
                  size: 15,
                  color: AppTheme.primaryGreen,
                ),
                const SizedBox(width: 4),
                Text(
                  sourceUrl.toLowerCase().endsWith('.pdf') ? 'Open Original PDF' : 'View Original Source',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.primaryGreen,
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
