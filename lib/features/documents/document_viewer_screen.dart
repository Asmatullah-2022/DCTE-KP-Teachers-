import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/document_model.dart';
import '../../providers/app_providers.dart';
import '../../widgets/error_state_view.dart';
import '../../widgets/source_attribution.dart';

/// Opens the document's `storageUrl` if present, otherwise the original
/// `sourceUrl` directly — the app is never dependent on Firebase Storage
/// when the official source can be opened directly.
class DocumentViewerScreen extends ConsumerWidget {
  final String documentId;
  const DocumentViewerScreen({super.key, required this.documentId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(documentsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Document'),
        actions: [
          FutureBuilder<DocumentModel?>(
            future: repo.getById(documentId),
            builder: (context, snapshot) {
              final doc = snapshot.data;
              if (doc == null) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.share_outlined),
                onPressed: () => Share.share(doc.sourceUrl),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<DocumentModel?>(
        future: repo.getById(documentId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final doc = snapshot.data;
          if (doc == null) return ErrorStateView.sourceUnavailable();

          final pdfUrl = doc.storageUrl ?? doc.sourceUrl;
          final isPdf = pdfUrl.toLowerCase().endsWith('.pdf');

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: SourceAttribution(
                  department: doc.department,
                  sourceUrl: doc.sourceUrl,
                  publishedDate: doc.publishedDate,
                ),
              ),
              Expanded(
                child: isPdf
                    ? _SafePdfView(url: pdfUrl, fallbackUrl: doc.sourceUrl)
                    : ErrorStateView.pdfFailed(
                        onRetry: () => launchUrl(Uri.parse(doc.sourceUrl), mode: LaunchMode.externalApplication),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SafePdfView extends StatefulWidget {
  final String url;
  final String fallbackUrl;
  const _SafePdfView({required this.url, required this.fallbackUrl});

  @override
  State<_SafePdfView> createState() => _SafePdfViewState();
}

class _SafePdfViewState extends State<_SafePdfView> {
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return ErrorStateView.pdfFailed(
        onRetry: () => launchUrl(Uri.parse(widget.fallbackUrl), mode: LaunchMode.externalApplication),
      );
    }
    return SfPdfViewer.network(
      widget.url,
      onDocumentLoadFailed: (details) => setState(() => _failed = true),
    );
  }
}
