/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../models/place.dart';
import '../services/collection_service.dart';
import '../services/i18n_service.dart';
import '../services/place_service.dart';

class PlaceSelection {
  final Place place;
  final String? collectionTitle;

  const PlaceSelection(this.place, this.collectionTitle);
}

class PlacePickerDialog extends StatefulWidget {
  final I18nService i18n;

  const PlacePickerDialog({super.key, required this.i18n});

  @override
  State<PlacePickerDialog> createState() => _PlacePickerDialogState();
}

class _PlacePickerDialogState extends State<PlacePickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  final List<PlaceSelection> _places = [];
  List<PlaceSelection> _filtered = [];
  bool _isLoading = true;
  late String _langCode;

  @override
  void initState() {
    super.initState();
    _langCode = widget.i18n.currentLanguage.split('_').first.toUpperCase();
    _searchController.addListener(_applyFilter);
    _loadPlaces();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPlaces() async {
    try {
      final collections = await CollectionService().loadCollections();
      final placeCollections = collections
          .where((c) => c.type == 'places' && c.storagePath != null)
          .toList();

      final placeService = PlaceService();
      for (final collection in placeCollections) {
        await placeService.initializeCollection(collection.storagePath!);
        final places = await placeService.loadAllPlaces();
        for (final place in places) {
          _places.add(PlaceSelection(place, collection.title));
        }
      }

      _places.sort((a, b) {
        final nameA = a.place.getName(_langCode).toLowerCase();
        final nameB = b.place.getName(_langCode).toLowerCase();
        return nameA.compareTo(nameB);
      });
    } catch (e) {
      // ignore errors, just show empty state
    }

    if (!mounted) return;
    setState(() {
      _filtered = List.from(_places);
      _isLoading = false;
    });
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _filtered = List.from(_places);
      });
      return;
    }

    setState(() {
      _filtered = _places.where((option) {
        final place = option.place;
        final name = place.getName(_langCode).toLowerCase();
        final address = place.address?.toLowerCase() ?? '';
        return name.contains(query) || address.contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: Container(
        width: 640,
        constraints: const BoxConstraints(maxHeight: 700),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  widget.i18n.t('places'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: widget.i18n.t('search_places'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? Center(
                          child: Text(
                            widget.i18n.t('no_places_found'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filtered.length,
                          itemBuilder: (context, index) {
                            final option = _filtered[index];
                            final place = option.place;
                            final name = place.getName(_langCode);
                            final subtitle = place.address?.isNotEmpty == true
                                ? place.address!
                                : place.coordinatesString;

                            return ListTile(
                              leading: const Icon(Icons.place_outlined),
                              title: Text(name),
                              subtitle: Text(subtitle),
                              trailing: option.collectionTitle != null
                                  ? Text(
                                      option.collectionTitle!,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    )
                                  : null,
                              onTap: () => Navigator.pop(context, option),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
