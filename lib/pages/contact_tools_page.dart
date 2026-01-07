/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import '../services/contact_service.dart';
import '../services/i18n_service.dart';
import 'contact_merge_page.dart';

/// Contact Tools page - provides utility tools for managing contacts
class ContactToolsPage extends StatelessWidget {
  final ContactService contactService;
  final I18nService i18n;
  final String collectionPath;
  final VoidCallback? onDeleteAll;
  final VoidCallback? onRefresh;

  const ContactToolsPage({
    super.key,
    required this.contactService,
    required this.i18n,
    required this.collectionPath,
    this.onDeleteAll,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(i18n.t('contact_tools')),
      ),
      body: ListView(
        children: [
          // Merge Duplicate Contacts
          _buildToolTile(
            context,
            icon: Icons.merge,
            title: i18n.t('merge_duplicates'),
            subtitle: i18n.t('merge_contacts_description'),
            onTap: () => _openMergeTool(context),
          ),
          const Divider(),
          // Delete All Cache/Metrics
          _buildToolTile(
            context,
            icon: Icons.cleaning_services,
            iconColor: Colors.orange,
            title: i18n.t('delete_all_cache'),
            subtitle: i18n.t('delete_all_cache_description'),
            onTap: () => _confirmDeleteCache(context),
          ),
          const Divider(),
          // Delete All Contacts (dangerous)
          _buildToolTile(
            context,
            icon: Icons.delete_forever,
            iconColor: Colors.red,
            title: i18n.t('delete_all_contacts'),
            subtitle: i18n.t('delete_all_contacts_description'),
            titleColor: Colors.red,
            onTap: () {
              Navigator.pop(context);
              onDeleteAll?.call();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteCache(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(i18n.t('delete_all_cache')),
        content: Text(i18n.t('delete_all_cache_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(i18n.t('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text(i18n.t('delete')),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final count = await contactService.deleteAllCacheFiles();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(i18n.t('cache_deleted', params: [count.toString()])),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
        onRefresh?.call();
      }
    }
  }

  Widget _buildToolTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
    Color? titleColor,
  }) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: (iconColor ?? Theme.of(context).colorScheme.primary).withValues(alpha: 0.15),
        child: Icon(icon, color: iconColor ?? Theme.of(context).colorScheme.primary),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: titleColor,
        ),
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  void _openMergeTool(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ContactMergePage(
          contactService: contactService,
          i18n: i18n,
        ),
      ),
    );
  }
}
