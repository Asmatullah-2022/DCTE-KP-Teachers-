import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants/app_constants.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About & Disclaimer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(AppConstants.appName, style: Theme.of(context).textTheme.titleLarge),
          Text(AppConstants.appSubtitle, style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)),
            child: const Text(AppConstants.disclaimer, style: TextStyle(fontSize: 14, height: 1.5)),
          ),
          const SizedBox(height: 20),
          Text('Official Sources', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _sourceLink(context, 'DCTE, Khyber Pakhtunkhwa', AppConstants.dcteBaseUrl),
          _sourceLink(context, 'KPESE, Khyber Pakhtunkhwa', AppConstants.kpeseBaseUrl),
          _sourceLink(context, 'KPESE Notifications', AppConstants.kpeseNotificationsUrl),
        ],
      ),
    );
  }

  Widget _sourceLink(BuildContext context, String label, String url) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.open_in_new, size: 18),
      title: Text(label),
      subtitle: Text(url, style: const TextStyle(fontSize: 12)),
      onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    );
  }
}
