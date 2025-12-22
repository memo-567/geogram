/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import '../services/device_apps_service.dart';
import '../services/devices_service.dart';
import '../services/i18n_service.dart';
import '../services/log_service.dart';
import 'remote_blog_browser_page.dart';
import 'remote_chat_browser_page.dart';
import 'events_browser_page.dart';
import 'report_browser_page.dart';

/// Page showing available apps on a remote device
class DeviceDetailPage extends StatefulWidget {
  final RemoteDevice device;

  const DeviceDetailPage({
    super.key,
    required this.device,
  });

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  final DeviceAppsService _appsService = DeviceAppsService();
  final I18nService _i18n = I18nService();

  Map<String, DeviceAppInfo> _apps = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadApps();
  }

  Future<void> _loadApps() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final apps = await _appsService.discoverApps(widget.device.callsign);
      setState(() {
        _apps = apps;
        _isLoading = false;
      });
    } catch (e) {
      LogService().log('DeviceDetailPage: Error loading apps: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _openApp(DeviceAppInfo app) {
    switch (app.type) {
      case 'blog':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RemoteBlogBrowserPage(
              device: widget.device,
            ),
          ),
        );
        break;
      case 'chat':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RemoteChatBrowserPage(
              device: widget.device,
            ),
          ),
        );
        break;
      case 'events':
        // Use existing EventsBrowserPage but filtered to this device
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const EventsBrowserPage(),
          ),
        );
        break;
      case 'alerts':
        // Use existing ReportBrowserPage but filtered to this device
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ReportBrowserPage(),
          ),
        );
        break;
    }
  }

  IconData _getAppIcon(String appType) {
    switch (appType) {
      case 'blog':
        return Icons.article;
      case 'chat':
        return Icons.chat_bubble;
      case 'events':
        return Icons.event;
      case 'alerts':
        return Icons.warning;
      default:
        return Icons.apps;
    }
  }

  Color _getAppColor(BuildContext context, String appType) {
    final theme = Theme.of(context);
    switch (appType) {
      case 'blog':
        return Colors.blue;
      case 'chat':
        return Colors.green;
      case 'events':
        return Colors.purple;
      case 'alerts':
        return Colors.orange;
      default:
        return theme.colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.displayName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadApps,
            tooltip: _i18n.t('refresh'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _i18n.t('error_loading_data'),
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: theme.textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadApps,
                        child: Text(_i18n.t('retry')),
                      ),
                    ],
                  ),
                )
              : _buildAppsList(theme),
    );
  }

  Widget _buildAppsList(ThemeData theme) {
    final availableApps = _apps.values.where((app) => app.isAvailable).toList();

    if (availableApps.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.apps_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No apps available',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'This device has no public data to browse',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: MediaQuery.of(context).size.width < 600 ? 2 : 3,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.2,
      ),
      itemCount: availableApps.length,
      itemBuilder: (context, index) {
        final app = availableApps[index];
        return _buildAppCard(theme, app);
      },
    );
  }

  Widget _buildAppCard(ThemeData theme, DeviceAppInfo app) {
    final appColor = _getAppColor(context, app.type);

    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () => _openApp(app),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: appColor.withValues(alpha: 0.2),
                child: Icon(
                  _getAppIcon(app.type),
                  size: 32,
                  color: appColor,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                app.displayName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                '${app.itemCount} items',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
