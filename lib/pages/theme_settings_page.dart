/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/app_theme_service.dart';
import '../services/i18n_service.dart';

class ThemeSettingsPage extends StatefulWidget {
  const ThemeSettingsPage({super.key});

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  final AppThemeService _themeService = AppThemeService();
  final I18nService _i18n = I18nService();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_i18n.t('app_theme')),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // Accent Color
          _buildSection(
            theme: theme,
            icon: Icons.palette_outlined,
            title: _i18n.t('color_theme'),
            child: _buildColorSelector(theme),
          ),

          const Divider(height: 1),

          // Font
          _buildSection(
            theme: theme,
            icon: Icons.text_fields,
            title: _i18n.t('font_family'),
            child: _buildFontSelector(theme),
          ),

          const Divider(height: 1),

          // Background Color
          _buildSection(
            theme: theme,
            icon: Icons.format_color_fill,
            title: _i18n.t('background_color'),
            subtitle: _i18n.t('dark_mode_only'),
            child: _buildBackgroundColorSelector(theme),
          ),

          const Divider(height: 1),

          // Background Image
          _buildBackgroundImageSection(theme),
        ],
      ),
    );
  }

  Widget _buildSection({
    required ThemeData theme,
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildColorSelector(ThemeData theme) {
    final currentTheme = _themeService.currentTheme;

    return Row(
      children: AppThemeService.availableThemes.map((config) {
        final isSelected = config.id == currentTheme;
        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: GestureDetector(
            onTap: () async {
              await _themeService.setTheme(config.id);
              if (mounted) setState(() {});
            },
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: config.seedColor,
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: Colors.white, width: 3)
                        : null,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: config.seedColor.withValues(alpha: 0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 24)
                      : null,
                ),
                const SizedBox(height: 6),
                Text(
                  _i18n.t('theme_${config.id.name}'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFontSelector(ThemeData theme) {
    final currentFont = _themeService.currentFont;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: AppFont.values.map((font) {
        final isSelected = font == currentFont;
        final fontName = _getFontDisplayName(font);

        return ChoiceChip(
          label: Text(fontName),
          selected: isSelected,
          onSelected: (selected) async {
            if (selected) {
              await _themeService.setFont(font);
              if (mounted) setState(() {});
            }
          },
        );
      }).toList(),
    );
  }

  String _getFontDisplayName(AppFont font) {
    switch (font) {
      case AppFont.system:
        return _i18n.t('system_default');
      case AppFont.roboto:
        return 'Roboto';
      case AppFont.openSans:
        return 'Open Sans';
      case AppFont.lato:
        return 'Lato';
      case AppFont.montserrat:
        return 'Montserrat';
    }
  }

  Widget _buildBackgroundColorSelector(ThemeData theme) {
    final currentBgColor = _themeService.backgroundColor;
    final colors = AppThemeService.availableBackgroundColors;

    return Row(
      children: [
        // Default option (no custom color)
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: GestureDetector(
            onTap: () async {
              await _themeService.setBackgroundColor(null);
              if (mounted) setState(() {});
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0A),
                shape: BoxShape.circle,
                border: currentBgColor == null
                    ? Border.all(color: theme.colorScheme.primary, width: 3)
                    : Border.all(color: theme.colorScheme.outlineVariant, width: 1),
              ),
              child: currentBgColor == null
                  ? Icon(Icons.check, color: theme.colorScheme.primary, size: 20)
                  : null,
            ),
          ),
        ),
        // Color options
        ...colors.skip(1).map((color) {
          final isSelected = currentBgColor?.value == color.value;
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () async {
                await _themeService.setBackgroundColor(color);
                if (mounted) setState(() {});
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: theme.colorScheme.primary, width: 3)
                      : Border.all(color: theme.colorScheme.outlineVariant, width: 1),
                ),
                child: isSelected
                    ? Icon(Icons.check, color: theme.colorScheme.primary, size: 20)
                    : null,
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildBackgroundImageSection(ThemeData theme) {
    final hasImage = _themeService.hasValidBackgroundImage;
    final imagePath = _themeService.backgroundImage;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.image_outlined, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _i18n.t('background_image'),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _i18n.t('dark_mode_only'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasImage && imagePath != null) ...[
            // Image preview
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  if (!kIsWeb)
                    Image.file(
                      File(imagePath),
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => Container(
                        height: 120,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IconButton.filled(
                      onPressed: () async {
                        await _themeService.clearBackgroundImage();
                        if (mounted) setState(() {});
                      },
                      icon: const Icon(Icons.close),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black54,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Select image button
          OutlinedButton.icon(
            onPressed: _pickBackgroundImage,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(hasImage ? _i18n.t('change_image') : _i18n.t('select_image')),
          ),
        ],
      ),
    );
  }

  Future<void> _pickBackgroundImage() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_i18n.t('not_available_web'))),
      );
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty && mounted) {
        final path = result.files.first.path;
        if (path != null) {
          await _themeService.setBackgroundImage(path);
          if (mounted) setState(() {});
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
