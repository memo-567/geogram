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

  const ContactToolsPage({
    super.key,
    required this.contactService,
    required this.i18n,
    required this.collectionPath,
    this.onDeleteAll,
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
            title: i18n.t('merge_contacts'),
            subtitle: i18n.t('merge_contacts_description'),
            onTap: () => _openMergeTool(context),
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
