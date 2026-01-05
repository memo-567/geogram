/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import '../models/profile.dart';
import '../services/i18n_service.dart';

/// Dialog for importing and exporting profiles
class ImportExportProfilesDialog extends StatelessWidget {
  final List<Profile> profiles;
  final VoidCallback onExportAll;
  final Function(Profile) onExportSingle;
  final VoidCallback onImport;

  const ImportExportProfilesDialog({
    super.key,
    required this.profiles,
    required this.onExportAll,
    required this.onExportSingle,
    required this.onImport,
  });

  @override
  Widget build(BuildContext context) {
    final i18n = I18nService();
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.import_export),
          const SizedBox(width: 12),
          Text(i18n.t('import_export_profiles')),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Info text
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      i18n.t('import_export_info'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Import section
            Text(
              i18n.t('import'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  onImport();
                },
                icon: const Icon(Icons.file_upload_outlined),
                label: Text(i18n.t('import_from_file')),
              ),
            ),
            const SizedBox(height: 24),

            // Export section
            Text(
              i18n.t('export'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: profiles.isNotEmpty
                    ? () {
                        Navigator.pop(context);
                        onExportAll();
                      }
                    : null,
                icon: const Icon(Icons.file_download_outlined),
                label: Text(i18n.t('export_all_profiles', params: ['${profiles.length}'])),
              ),
            ),
            const SizedBox(height: 16),

            // Individual profile export
            if (profiles.isNotEmpty) ...[
              Text(
                i18n.t('or_export_individual'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.outline.withOpacity(0.5),
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: profiles.length,
                  itemBuilder: (context, index) {
                    final profile = profiles[index];
                    return ListTile(
                      dense: true,
                      leading: _buildProfileAvatar(profile),
                      title: Text(profile.callsign),
                      subtitle: profile.nickname.isNotEmpty
                          ? Text(profile.nickname)
                          : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.file_download_outlined, size: 20),
                        tooltip: i18n.t('export_profile'),
                        onPressed: () {
                          Navigator.pop(context);
                          onExportSingle(profile);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(i18n.t('close')),
        ),
      ],
    );
  }

  Widget _buildProfileAvatar(Profile profile) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _getColorFromName(profile.preferredColor),
      ),
      child: Center(
        child: Text(
          profile.callsign.isNotEmpty ? profile.callsign.substring(0, 2) : '??',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Color _getColorFromName(String colorName) {
    switch (colorName.toLowerCase()) {
      case 'red':
        return Colors.red;
      case 'blue':
        return Colors.blue;
      case 'green':
        return Colors.green;
      case 'yellow':
        return Colors.yellow;
      case 'purple':
        return Colors.purple;
      case 'orange':
        return Colors.orange;
      case 'pink':
        return Colors.pink;
      case 'cyan':
        return Colors.cyan;
      default:
        return Colors.blue;
    }
  }
}
