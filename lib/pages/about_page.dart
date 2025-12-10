import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../version.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  void _launchURL(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open $url'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About Geogram'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App Icon and Title
            Center(
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/geogram_icon_transparent.png',
                      width: 100,
                      height: 100,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Connected, together',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Version $appVersion',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Tagline
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'True P2P Privacy • No Servers Required',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Description
            Text(
              'About',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Geogram is a privacy-first communication platform that connects devices directly—no central servers, no data collection, no compromise.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Text(
              'Using WebRTC for direct peer-to-peer connections, Bluetooth mesh networking, and cryptographically signed messages, Geogram ensures your conversations stay between you and your contacts.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),

            const SizedBox(height: 32),

            // Features
            Text(
              'Key Features',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            _buildFeature(
              context,
              Icons.link,
              'Direct P2P via WebRTC',
              'Connect directly to other devices—no relay servers',
            ),
            _buildFeature(
              context,
              Icons.lock,
              'End-to-End Encryption',
              'Messages cryptographically signed with NOSTR keys',
            ),
            _buildFeature(
              context,
              Icons.offline_bolt,
              'Offline-First Design',
              'Works without internet via Bluetooth mesh',
            ),
            _buildFeature(
              context,
              Icons.devices,
              'Multi-Platform',
              'Android, Desktop, Web, and embedded devices',
            ),
            _buildFeature(
              context,
              Icons.hub,
              'Smart Routing',
              'Automatic fallback: LAN → WebRTC → Station → Bluetooth',
            ),
            _buildFeature(
              context,
              Icons.verified_user,
              'Verified Messages',
              'Every message signed and verified—no spoofing',
            ),

            const SizedBox(height: 32),

            // Communication Channels
            Text(
              'Connection Methods',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            _buildChannel(
              context,
              Icons.wifi,
              'Local Network (LAN)',
              'Fastest—direct HTTP on same WiFi network',
            ),
            _buildChannel(
              context,
              Icons.link,
              'WebRTC P2P',
              'Direct connection via NAT traversal—true privacy',
            ),
            _buildChannel(
              context,
              Icons.cloud_outlined,
              'Station Relay',
              'Fallback relay when P2P unavailable',
            ),
            _buildChannel(
              context,
              Icons.bluetooth,
              'Bluetooth Mesh',
              'Offline communication—no internet needed',
            ),

            const SizedBox(height: 32),

            // Collections Feature
            Text(
              'Collections',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Geogram Desktop includes a powerful Collections feature for sharing files and folders offline:',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            _buildFeature(
              context,
              Icons.folder,
              'File Sharing',
              'Create collections of files to share with others',
            ),
            _buildFeature(
              context,
              Icons.vpn_key,
              'NOSTR-Based IDs',
              'Collections identified by npub keys',
            ),
            _buildFeature(
              context,
              Icons.security,
              'Access Control',
              'Public, private, or restricted visibility',
            ),
            _buildFeature(
              context,
              Icons.sync,
              'Offline Sync',
              'Share collections via BLE or local network',
            ),

            const SizedBox(height: 32),

            // License
            Text(
              'License',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Copyright 2025 Geogram Contributors\n\n'
              'Licensed under the Apache License, Version 2.0',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _launchURL(
                context,
                'https://www.apache.org/licenses/LICENSE-2.0',
              ),
              icon: const Icon(Icons.open_in_new),
              label: const Text('View License'),
            ),

            const SizedBox(height: 32),

            // Links
            Text(
              'Links',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            _buildLink(
              context,
              Icons.code,
              'GitHub Repository',
              'https://github.com/geograms/central',
            ),
            _buildLink(
              context,
              Icons.bug_report,
              'Report Issues',
              'https://github.com/geograms/central/issues',
            ),
            _buildLink(
              context,
              Icons.description,
              'Documentation',
              'https://github.com/geograms/central/blob/main/docs/README.md',
            ),
            _buildLink(
              context,
              Icons.forum,
              'Discussions',
              'https://github.com/geograms/central/discussions',
            ),

            const SizedBox(height: 32),

            // Attribution
            Center(
              child: Text(
                'Your data, your devices, your privacy.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildFeature(
    BuildContext context,
    IconData icon,
    String title,
    String description,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 24,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannel(
    BuildContext context,
    IconData icon,
    String title,
    String description,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 32,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLink(
    BuildContext context,
    IconData icon,
    String title,
    String url,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _launchURL(context, url),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                ),
              ),
              Icon(
                Icons.open_in_new,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
