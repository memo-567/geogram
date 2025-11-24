/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import '../models/market_shop.dart';
import '../models/market_item.dart';
import '../services/market_service.dart';
import '../services/profile_service.dart';
import '../services/i18n_service.dart';
import 'shop_settings_page.dart';

/// Marketplace browser page with responsive layout
class MarketBrowserPage extends StatefulWidget {
  final String collectionPath;
  final String collectionTitle;

  const MarketBrowserPage({
    Key? key,
    required this.collectionPath,
    required this.collectionTitle,
  }) : super(key: key);

  @override
  State<MarketBrowserPage> createState() => _MarketBrowserPageState();
}

class _MarketBrowserPageState extends State<MarketBrowserPage> {
  final MarketService _marketService = MarketService();
  final ProfileService _profileService = ProfileService();
  final I18nService _i18n = I18nService();
  final TextEditingController _searchController = TextEditingController();

  MarketShop? _shop;
  List<String> _categories = [];
  List<MarketItem> _allItems = [];
  List<MarketItem> _filteredItems = [];
  MarketItem? _selectedItem;
  String? _selectedCategory;
  bool _isLoading = true;
  String? _currentUserNpub;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterItems);
    _initialize();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    final profile = _profileService.getProfile();
    _currentUserNpub = profile.npub;

    await _marketService.initializeCollection(
      widget.collectionPath,
      creatorNpub: _currentUserNpub,
    );

    await _loadMarketplace();
  }

  Future<void> _loadMarketplace() async {
    setState(() => _isLoading = true);

    _shop = _marketService.getShop();
    _categories = await _marketService.getCategories();
    _allItems = await _marketService.loadItems();

    setState(() {
      _filteredItems = _allItems;
      _isLoading = false;
    });
  }

  void _filterItems() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredItems = _allItems.where((item) {
        if (_selectedCategory != null && item.categoryPath != _selectedCategory) {
          return false;
        }
        if (query.isEmpty) return true;

        final title = item.getTitle('EN')?.toLowerCase() ?? '';
        final description = item.getDescription('EN')?.toLowerCase() ?? '';
        return title.contains(query) || description.contains(query);
      }).toList();
    });
  }

  void _selectCategory(String? category) {
    setState(() {
      _selectedCategory = category;
      _filterItems();
    });
  }

  void _selectItem(MarketItem item) {
    setState(() => _selectedItem = item);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_shop?.shopName ?? _i18n.t('collection_type_market')),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            onPressed: () {
              // TODO: Open cart view
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cart feature coming soon')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.receipt_long),
            onPressed: () {
              // TODO: Open orders view
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Orders feature coming soon')),
              );
            },
          ),
          if (_shop?.ownerNpub == _currentUserNpub)
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _showAddItemDialog,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _shop == null
              ? _buildNoShopView(theme)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isWideScreen = constraints.maxWidth >= 600;
                    if (isWideScreen) {
                      return Row(
                        children: [
                          // Left panel: Categories and Items
                          Expanded(
                            child: _buildItemsPanel(theme, isWideScreen: true),
                          ),
                          // Right panel: Item Detail
                          if (_selectedItem != null)
                            SizedBox(
                              width: 400,
                              child: _buildItemDetail(theme),
                            ),
                        ],
                      );
                    } else {
                      // Mobile: Single panel
                      return _selectedItem == null
                          ? _buildItemsPanel(theme, isWideScreen: false)
                          : _buildItemDetailMobile(theme);
                    }
                  },
                ),
    );
  }

  Widget _buildNoShopView(ThemeData theme) {
    final isOwner = _shop == null && _currentUserNpub != null;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.store, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            isOwner ? _i18n.t('create_your_shop') : _i18n.t('no_shop_available'),
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            isOwner
                ? _i18n.t('setup_marketplace_to_sell')
                : _i18n.t('collection_no_shop_yet'),
            style: theme.textTheme.bodyMedium,
          ),
          if (isOwner) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _showCreateShopDialog,
              icon: const Icon(Icons.add),
              label: Text(_i18n.t('create_shop')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemsPanel(ThemeData theme, {required bool isWideScreen}) {
    return Column(
      children: [
        // Shop header
        if (_shop != null) _buildShopHeader(theme),

        // Search and filters
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search items...',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Icons.filter_list),
                tooltip: 'Filter by category',
                onSelected: _selectCategory,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: null,
                    child: Text('All Categories'),
                  ),
                  ..._categories.map((category) => PopupMenuItem(
                        value: category,
                        child: Text(category),
                      )),
                ],
              ),
            ],
          ),
        ),

        // Items list/grid
        Expanded(
          child: _filteredItems.isEmpty
              ? Center(
                  child: Text(
                    'No items found',
                    style: theme.textTheme.bodyLarge,
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: isWideScreen ? 3 : 2,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: _filteredItems.length,
                  itemBuilder: (context, index) {
                    final item = _filteredItems[index];
                    return _buildItemCard(item, theme);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildShopHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withOpacity(0.3),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withOpacity(0.2),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.store,
            size: 32,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _shop!.shopName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_shop!.tagline != null)
                  Text(
                    _shop!.tagline!,
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          if (_shop!.ownerNpub == _currentUserNpub)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ShopSettingsPage(
                      collectionPath: widget.collectionPath,
                    ),
                  ),
                );
                // Reload shop after returning from settings
                _loadMarketplace();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildItemCard(MarketItem item, ThemeData theme) {
    final title = item.getTitle('EN') ?? 'Untitled';
    final isOwner = _shop?.ownerNpub == _currentUserNpub;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _selectItem(item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image placeholder
            Container(
              height: 120,
              color: theme.colorScheme.surfaceVariant,
              child: Center(
                child: Icon(
                  _getItemIcon(item.type),
                  size: 48,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.formattedPrice,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        if (!item.isAvailable)
                          Chip(
                            label: Text(
                              'Out of Stock',
                              style: theme.textTheme.labelSmall,
                            ),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          )
                        else if (isOwner)
                          Text(
                            'Stock: ${item.numericStock ?? '∞'}',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemDetail(ThemeData theme) {
    if (_selectedItem == null) return const SizedBox.shrink();

    final item = _selectedItem!;
    final title = item.getTitle('EN') ?? 'Untitled';
    final description = item.getDescription('EN') ?? 'No description';
    final isOwner = _shop?.ownerNpub == _currentUserNpub;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: theme.colorScheme.outline.withOpacity(0.2),
          ),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outline.withOpacity(0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isOwner)
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () {
                      // TODO: Edit item
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Edit item coming soon')),
                      );
                    },
                  ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Price
                  Text(
                    item.formattedPrice,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Description
                  Text(description, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 16),

                  // Status
                  _buildInfoRow('Status', item.status.toFileString(), theme),
                  _buildInfoRow('Type', item.type.name, theme),
                  if (!item.isUnlimitedStock)
                    _buildInfoRow('Stock', '${item.numericStock}', theme),
                  _buildInfoRow('Location', item.location, theme),
                  _buildInfoRow('Radius', '${item.radius} ${item.radiusUnit}', theme),

                  const SizedBox(height: 24),

                  // Add to cart button
                  if (!isOwner && item.isAvailable)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () {
                          // TODO: Add to cart
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Add to cart coming soon')),
                          );
                        },
                        icon: const Icon(Icons.add_shopping_cart),
                        label: const Text('Add to Cart'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemDetailMobile(ThemeData theme) {
    if (_selectedItem == null) return const SizedBox.shrink();

    final item = _selectedItem!;
    final title = item.getTitle('EN') ?? 'Untitled';
    final description = item.getDescription('EN') ?? 'No description';
    final isOwner = _shop?.ownerNpub == _currentUserNpub;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() => _selectedItem = null);
          },
        ),
        actions: [
          if (isOwner)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () {
                // TODO: Edit item
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Edit item coming soon')),
                );
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Price
            Text(
              item.formattedPrice,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Description
            Text(description, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 16),

            // Details
            _buildInfoRow('Status', item.status.toFileString(), theme),
            _buildInfoRow('Type', item.type.name, theme),
            if (!item.isUnlimitedStock)
              _buildInfoRow('Stock', '${item.numericStock}', theme),
            _buildInfoRow('Location', item.location, theme),
            _buildInfoRow('Radius', '${item.radius} ${item.radiusUnit}', theme),

            const SizedBox(height: 24),

            // Add to cart button
            if (!isOwner && item.isAvailable)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    // TODO: Add to cart
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Add to cart coming soon')),
                    );
                  },
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('Add to Cart'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getItemIcon(ItemType type) {
    switch (type) {
      case ItemType.physical:
        return Icons.inventory_2;
      case ItemType.digital:
        return Icons.cloud_download;
      case ItemType.service:
        return Icons.build;
    }
  }

  Future<void> _showCreateShopDialog() async {
    // Navigate to shop settings page for comprehensive shop creation
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ShopSettingsPage(
          collectionPath: widget.collectionPath,
        ),
      ),
    );
    // Reload marketplace after returning from settings
    _loadMarketplace();
  }

  Future<void> _createShop({
    required String shopName,
    required String shopOwner,
    required String ownerNpub,
    String? tagline,
    String? currency,
  }) async {
    try {
      final now = DateTime.now().toIso8601String().replaceAll(':', '_');

      final shop = MarketShop(
        shopName: shopName,
        shopOwner: shopOwner,
        ownerNpub: ownerNpub,
        created: now,
        tagline: tagline,
        currency: currency ?? 'USD',
      );

      await _marketService.saveShop(shop);
      await _loadMarketplace();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_i18n.t('shop_created'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_i18n.t('error_creating_shop'))),
        );
      }
    }
  }

  Future<void> _showAddItemDialog() async {
    if (_shop == null) return;

    await showDialog(
      context: context,
      builder: (context) => _AddItemDialog(
        onAddItem: _addItem,
        categories: _categories,
        shopCurrency: _shop!.currency,
      ),
    );
  }

  Future<void> _addItem({
    required String title,
    required double price,
    String? description,
    required ItemType type,
    required ItemStatus status,
    String? categoryPath,
    String? stock,
  }) async {
    try {
      final now = DateTime.now().toIso8601String().replaceAll(':', '_');
      final itemId = DateTime.now().millisecondsSinceEpoch.toString();

      // Get location from profile (default values for required fields)
      final profile = _profileService.getProfile();

      final item = MarketItem(
        itemId: itemId,
        created: now,
        updated: now,
        status: status,
        type: type,
        deliveryMethod: type == ItemType.digital ? DeliveryMethod.digital : DeliveryMethod.physical,
        location: profile.locationName ?? 'Unknown',
        latitude: profile.latitude ?? 0.0,
        longitude: profile.longitude ?? 0.0,
        radius: 50, // Default 50km radius
        titles: {'EN': title},
        price: price,
        currency: _shop?.currency ?? 'EUR',
        stock: stock == null || stock.isEmpty ? 'unlimited' : int.tryParse(stock) ?? 'unlimited',
        sold: 0,
        minOrder: 1,
        maxOrder: 100,
        rating: 0.0,
        reviewCount: 0,
        descriptions: description != null && description.isNotEmpty ? {'EN': description} : {},
        specifications: {},
        categoryPath: categoryPath,
        galleryFiles: [],
        metadata: {},
      );

      await _marketService.saveItem(item);
      await _loadMarketplace();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_i18n.t('item_added'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_i18n.t('error_adding_item'))),
        );
      }
    }
  }
}

class _CreateShopDialog extends StatefulWidget {
  final Function({
    required String shopName,
    required String shopOwner,
    required String ownerNpub,
    String? tagline,
    String? currency,
  }) onCreateShop;
  final String ownerName;
  final String ownerNpub;

  const _CreateShopDialog({
    Key? key,
    required this.onCreateShop,
    required this.ownerName,
    required this.ownerNpub,
  }) : super(key: key);

  @override
  State<_CreateShopDialog> createState() => _CreateShopDialogState();
}

class _CreateShopDialogState extends State<_CreateShopDialog> {
  final I18nService _i18n = I18nService();
  final _formKey = GlobalKey<FormState>();
  final _shopNameController = TextEditingController();
  final _taglineController = TextEditingController();
  String _currency = 'EUR';
  bool _isCreating = false;

  @override
  void dispose() {
    _shopNameController.dispose();
    _taglineController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isCreating = true);

    await widget.onCreateShop(
      shopName: _shopNameController.text.trim(),
      shopOwner: widget.ownerName,
      ownerNpub: widget.ownerNpub,
      tagline: _taglineController.text.trim().isEmpty
          ? null
          : _taglineController.text.trim(),
      currency: _currency,
    );

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(_i18n.t('create_shop')),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _shopNameController,
                decoration: InputDecoration(
                  labelText: _i18n.t('shop_name'),
                  hintText: _i18n.t('shop_name_hint'),
                  border: const OutlineInputBorder(),
                ),
                autofocus: true,
                enabled: !_isCreating,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return _i18n.t('shop_name_required');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _taglineController,
                decoration: InputDecoration(
                  labelText: '${_i18n.t('tagline')} (${_i18n.t('optional')})',
                  hintText: _i18n.t('tagline_hint'),
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
                enabled: !_isCreating,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _currency,
                decoration: InputDecoration(
                  labelText: _i18n.t('currency'),
                  border: const OutlineInputBorder(),
                ),
                items: ['USD', 'EUR', 'GBP', 'BTC', 'SAT'].map((currency) {
                  return DropdownMenuItem(
                    value: currency,
                    child: Text(currency),
                  );
                }).toList(),
                onChanged: _isCreating ? null : (value) {
                  if (value != null) {
                    setState(() => _currency = value);
                  }
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.of(context).pop(),
          child: Text(_i18n.t('cancel')),
        ),
        FilledButton(
          onPressed: _isCreating ? null : _create,
          child: _isCreating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_i18n.t('create')),
        ),
      ],
    );
  }
}

class _AddItemDialog extends StatefulWidget {
  final Function({
    required String title,
    required double price,
    String? description,
    required ItemType type,
    required ItemStatus status,
    String? categoryPath,
    String? stock,
  }) onAddItem;
  final List<String> categories;
  final String shopCurrency;

  const _AddItemDialog({
    Key? key,
    required this.onAddItem,
    required this.categories,
    required this.shopCurrency,
  }) : super(key: key);

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final I18nService _i18n = I18nService();
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _stockController = TextEditingController();

  ItemType _type = ItemType.physical;
  ItemStatus _status = ItemStatus.draft;
  String? _categoryPath;
  bool _isAdding = false;

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isAdding = true);

    final price = double.tryParse(_priceController.text.trim()) ?? 0.0;

    await widget.onAddItem(
      title: _titleController.text.trim(),
      price: price,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      type: _type,
      status: _status,
      categoryPath: _categoryPath,
      stock: _stockController.text.trim().isEmpty
          ? null
          : _stockController.text.trim(),
    );

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_i18n.t('add_item')),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: _i18n.t('item_title'),
                    hintText: _i18n.t('item_title_hint'),
                    border: const OutlineInputBorder(),
                  ),
                  autofocus: true,
                  enabled: !_isAdding,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return _i18n.t('item_title_required');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _priceController,
                  decoration: InputDecoration(
                    labelText: '${_i18n.t('price')} (${widget.shopCurrency})',
                    hintText: '0.00',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  enabled: !_isAdding,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return _i18n.t('price_required');
                    }
                    if (double.tryParse(value.trim()) == null) {
                      return _i18n.t('invalid_price');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: '${_i18n.t('description')} (${_i18n.t('optional')})',
                    hintText: _i18n.t('item_description_hint'),
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  enabled: !_isAdding,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<ItemType>(
                  value: _type,
                  decoration: InputDecoration(
                    labelText: _i18n.t('item_type'),
                    border: const OutlineInputBorder(),
                  ),
                  items: ItemType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(_i18n.t('item_type_${type.name}')),
                    );
                  }).toList(),
                  onChanged: _isAdding ? null : (value) {
                    if (value != null) {
                      setState(() => _type = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<ItemStatus>(
                  value: _status,
                  decoration: InputDecoration(
                    labelText: _i18n.t('status'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [ItemStatus.draft, ItemStatus.available].map((status) {
                    return DropdownMenuItem(
                      value: status,
                      child: Text(_i18n.t('item_status_${status.name}')),
                    );
                  }).toList(),
                  onChanged: _isAdding ? null : (value) {
                    if (value != null) {
                      setState(() => _status = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                if (widget.categories.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: _categoryPath,
                    decoration: InputDecoration(
                      labelText: '${_i18n.t('category')} (${_i18n.t('optional')})',
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(_i18n.t('uncategorized')),
                      ),
                      ...widget.categories.map((category) {
                        return DropdownMenuItem(
                          value: category,
                          child: Text(category),
                        );
                      }).toList(),
                    ],
                    onChanged: _isAdding ? null : (value) {
                      setState(() => _categoryPath = value);
                    },
                  ),
                if (widget.categories.isNotEmpty)
                  const SizedBox(height: 16),
                TextFormField(
                  controller: _stockController,
                  decoration: InputDecoration(
                    labelText: '${_i18n.t('stock')} (${_i18n.t('optional')})',
                    hintText: _i18n.t('stock_hint'),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  enabled: !_isAdding,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isAdding ? null : () => Navigator.of(context).pop(),
          child: Text(_i18n.t('cancel')),
        ),
        FilledButton(
          onPressed: _isAdding ? null : _add,
          child: _isAdding
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_i18n.t('add')),
        ),
      ],
    );
  }
}
