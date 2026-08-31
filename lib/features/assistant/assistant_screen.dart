import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_providers.dart';

/// Architecture for a future AI assistant: the client NEVER holds an AI
/// API key. It calls the `askAssistant` HTTPS Callable Cloud Function
/// (see functions/src/ai/extract.ts), which queries indexed official
/// documents and returns an answer plus its source document/page.
/// Not wired to a live model in this MVP — the function currently returns
/// a stub response so the UI and plumbing are ready to connect a real,
/// trusted backend AI service.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _ChatMessage {
  final String text;
  final bool isUser;
  final String? sourceDocument;
  final int? sourcePage;
  _ChatMessage(this.text, this.isUser, {this.sourceDocument, this.sourcePage});
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _controller = TextEditingController();
  final List<_ChatMessage> _messages = [];
  bool _sending = false;

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_ChatMessage(text, true));
      _sending = true;
      _controller.clear();
    });

    try {
      final functions = ref.read(functionsProvider);
      final callable = functions.httpsCallable('askAssistant');
      final result = await callable.call<Map<String, dynamic>>({'question': text});
      final data = result.data;
      setState(() {
        _messages.add(_ChatMessage(
          data['answer'] as String? ?? 'No answer available yet.',
          false,
          sourceDocument: data['sourceDocumentTitle'] as String?,
          sourcePage: data['sourcePage'] as int?,
        ));
      });
    } on FirebaseFunctionsException catch (e) {
      setState(() {
        _messages.add(_ChatMessage(
          'The assistant is unavailable right now (${e.code}). Please check the Curriculum or Documents section directly.',
          false,
        ));
      });
    } finally {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DCTE Assistant')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.blue.shade50,
            padding: const EdgeInsets.all(12),
            child: const Text(
              'Answers are generated from indexed official documents only. Every answer includes its source document and page when available. This assistant never fabricates official information.',
              style: TextStyle(fontSize: 12.5),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, i) {
                final m = _messages[i];
                return Align(
                  alignment: m.isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    constraints: const BoxConstraints(maxWidth: 320),
                    decoration: BoxDecoration(
                      color: m.isUser ? Colors.green.shade100 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.text),
                        if (m.sourceDocument != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Source: ${m.sourceDocument}${m.sourcePage != null ? ' (p. ${m.sourcePage})' : ''}',
                              style: const TextStyle(fontSize: 11, color: Colors.black54),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'e.g. "Grade 5 Mathematics Semester I topics?"',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
