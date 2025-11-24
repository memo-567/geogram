/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import '../models/market_shop.dart';
import '../services/market_service.dart';
import '../services/profile_service.dart';
import '../services/log_service.dart';

/// Page for managing shop settings
class ShopSettingsPage extends StatefulWidget {
  final String collectionPath;

  const ShopSettingsPage({
    super.key,
    required this.collectionPath,
  });

  @override
  State<ShopSettingsPage> createState() => _ShopSettingsPageState();
}

class _ShopSettingsPageState extends State<ShopSettingsPage> {
  final MarketService _marketService = MarketService();
  final ProfileService _profileService = ProfileService();

  MarketShop? _shop;
  bool _isLoading = false;
  bool _isOwner = false;

  // Controllers for form fields
  final _shopNameController = TextEditingController();
  final _taglineController = TextEditingController();
  final _currencyController = TextEditingController();
  final _contactEmailController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _locationController = TextEditingController();

  // Multilanguage controllers
  final Map<String, TextEditingController> _descriptionControllers = {};
  final Map<String, TextEditingController> _paymentInfoControllers = {};
  final Map<String, TextEditingController> _shippingInfoControllers = {};
  final Map<String, TextEditingController> _returnPolicyControllers = {};

  final List<String> _supportedLanguages = ['EN', 'PT', 'ES', 'FR', 'DE'];
  final List<String> _paymentMethodOptions = [
    'bitcoin',
    'lightning',
    'bank-transfer',
    'paypal',
    'cash',
    'check',
    'monero',
    'trade',
    'service'
  ];
  final List<String> _shippingOptionsList = [
    'standard',
    'express',
    'pickup',
    'overnight',
    'international'
  ];

  List<String> _selectedPaymentMethods = [];
  List<String> _selectedShippingOptions = [];
  List<String> _selectedLanguages = [];
  ShopStatus _selectedStatus = ShopStatus.active;

  @override
  void initState() {
    super.initState();
    _loadShop();
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _taglineController.dispose();
    _currencyController.dispose();
    _contactEmailController.dispose();
    _contactPhoneController.dispose();
    _locationController.dispose();
    for (var controller in _descriptionControllers.values) {
      controller.dispose();
    }
    for (var controller in _paymentInfoControllers.values) {
      controller.dispose();
    }
    for (var controller in _shippingInfoControllers.values) {
      controller.dispose();
    }
    for (var controller in _returnPolicyControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Load shop settings
  Future<void> _loadShop() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _marketService.initializeCollection(widget.collectionPath);
      _shop = _marketService.getShop();

      // Check if current user is shop owner
      final profile = _profileService.getProfile();
      _isOwner = _shop?.ownerNpub == profile.npub;

      if (_shop != null) {
        // Populate form fields
        _shopNameController.text = _shop!.shopName;
        _taglineController.text = _shop!.tagline ?? '';
        _currencyController.text = _shop!.currency;
        _contactEmailController.text = _shop!.contactEmail ?? '';
        _contactPhoneController.text = _shop!.contactPhone ?? '';
        _locationController.text = _shop!.location ?? '';

        _selectedPaymentMethods = List.from(_shop!.paymentMethods);
        _selectedShippingOptions = List.from(_shop!.shippingOptions);
        _selectedLanguages = List.from(_shop!.languages);
        _selectedStatus = _shop!.status;

        // Initialize multilanguage controllers
        for (var lang in _supportedLanguages) {
          _descriptionControllers[lang] = TextEditingController(
            text: _shop!.descriptions[lang] ?? '',
          );
          _paymentInfoControllers[lang] = TextEditingController(
            text: _shop!.paymentInfo[lang] ?? '',
          );
          _shippingInfoControllers[lang] = TextEditingController(
            text: _shop!.shippingInfo[lang] ?? '',
          );
          _returnPolicyControllers[lang] = TextEditingController(
            text: _shop!.returnPolicies[lang] ?? '',
          );
        }
      } else {
        // Initialize new shop
        final profile = _profileService.getProfile();
        if (profile.npub.isEmpty) {
          _showError('Please set up your NOSTR keys in your profile first');
        } else {
          _selectedLanguages = ['EN'];
          _selectedStatus = ShopStatus.active;
          _currencyController.text = 'USD';

          // Initialize controllers for supported languages
          for (var lang in _supportedLanguages) {
            _descriptionControllers[lang] = TextEditingController();
            _paymentInfoControllers[lang] = TextEditingController();
            _shippingInfoControllers[lang] = TextEditingController();
            _returnPolicyControllers[lang] = TextEditingController();
          }
        }
      }
    } catch (e) {
      _showError('Failed to load shop: $e');
      LogService().log('ShopSettingsPage: Error loading shop: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Save shop settings
  Future<void> _saveShop() async {
    if (!_isOwner && _shop != null) {
      _showError('Only the shop owner can modify settings');
      return;
    }

    // Validate required fields
    if (_shopNameController.text.trim().isEmpty) {
      _showError('Shop name is required');
      return;
    }

    final profile = _profileService.getProfile();
    if (profile.npub.isEmpty) {
      _showError('Please set up your NOSTR keys in your profile first');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Collect multilanguage fields
      final descriptions = <String, String>{};
      final paymentInfo = <String, String>{};
      final shippingInfo = <String, String>{};
      final returnPolicies = <String, String>{};

      for (var lang in _selectedLanguages) {
        final desc = _descriptionControllers[lang]?.text.trim();
        if (desc != null && desc.isNotEmpty) {
          descriptions[lang] = desc;
        }

        final payment = _paymentInfoControllers[lang]?.text.trim();
        if (payment != null && payment.isNotEmpty) {
          paymentInfo[lang] = payment;
        }

        final shipping = _shippingInfoControllers[lang]?.text.trim();
        if (shipping != null && shipping.isNotEmpty) {
          shippingInfo[lang] = shipping;
        }

        final returns = _returnPolicyControllers[lang]?.text.trim();
        if (returns != null && returns.isNotEmpty) {
          returnPolicies[lang] = returns;
        }
      }

      // Create or update shop
      final now = DateTime.now();
      final created = _shop?.created ??
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}_${now.second.toString().padLeft(2, '0')}';

      final shop = MarketShop(
        shopName: _shopNameController.text.trim(),
        shopOwner: profile.callsign,
        ownerNpub: profile.npub,
        created: created,
        status: _selectedStatus,
        tagline: _taglineController.text.trim().isNotEmpty
            ? _taglineController.text.trim()
            : null,
        currency: _currencyController.text.trim(),
        paymentMethods: _selectedPaymentMethods,
        shippingOptions: _selectedShippingOptions,
        contactEmail: _contactEmailController.text.trim().isNotEmpty
            ? _contactEmailController.text.trim()
            : null,
        contactPhone: _contactPhoneController.text.trim().isNotEmpty
            ? _contactPhoneController.text.trim()
            : null,
        location: _locationController.text.trim().isNotEmpty
            ? _locationController.text.trim()
            : null,
        languages: _selectedLanguages,
        descriptions: descriptions,
        paymentInfo: paymentInfo,
        shippingInfo: shippingInfo,
        returnPolicies: returnPolicies,
        metadata: {
          'npub': profile.npub,
        },
      );

      await _marketService.saveShop(shop);
      _shop = shop;
      _isOwner = true;

      _showSuccess('Shop settings saved successfully');
    } catch (e) {
      _showError('Failed to save shop: $e');
      LogService().log('ShopSettingsPage: Error saving shop: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Shop Settings'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shop Settings'),
        actions: [
          if (_isOwner || _shop == null)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _saveShop,
              tooltip: 'Save Settings',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Warning if not owner
          if (!_isOwner && _shop != null)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.warning,
                        color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'You are not the shop owner. Settings are read-only.',
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Basic Information
          _buildSection(
            theme,
            'Basic Information',
            [
              TextField(
                controller: _shopNameController,
                decoration: const InputDecoration(
                  labelText: 'Shop Name *',
                  hintText: 'Enter your shop name',
                  border: OutlineInputBorder(),
                ),
                enabled: _isOwner || _shop == null,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _taglineController,
                decoration: const InputDecoration(
                  labelText: 'Tagline',
                  hintText: 'Short description of your shop',
                  border: OutlineInputBorder(),
                ),
                enabled: _isOwner || _shop == null,
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<ShopStatus>(
                initialValue: _selectedStatus,
                decoration: const InputDecoration(
                  labelText: 'Shop Status',
                  border: OutlineInputBorder(),
                ),
                items: ShopStatus.values.map((status) {
                  return DropdownMenuItem(
                    value: status,
                    child: Text(status.name),
                  );
                }).toList(),
                onChanged: (_isOwner || _shop == null)
                    ? (value) {
                        if (value != null) {
                          setState(() {
                            _selectedStatus = value;
                          });
                        }
                      }
                    : null,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Contact Information
          _buildSection(
            theme,
            'Contact Information',
            [
              TextField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  hintText: 'City, Country',
                  border: OutlineInputBorder(),
                ),
                enabled: _isOwner || _shop == null,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _contactEmailController,
                decoration: const InputDecoration(
                  labelText: 'Contact Email',
                  hintText: 'shop@example.com',
                  border: OutlineInputBorder(),
                ),
                enabled: _isOwner || _shop == null,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _contactPhoneController,
                decoration: const InputDecoration(
                  labelText: 'Contact Phone',
                  hintText: '+351-XXX-XXX-XXX',
                  border: OutlineInputBorder(),
                ),
                enabled: _isOwner || _shop == null,
                keyboardType: TextInputType.phone,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Currency and Payment
          _buildSection(
            theme,
            'Currency & Payment',
            [
              TextField(
                controller: _currencyController,
                decoration: const InputDecoration(
                  labelText: 'Currency',
                  hintText: 'USD, EUR, GBP, etc.',
                  border: OutlineInputBorder(),
                ),
                enabled: _isOwner || _shop == null,
              ),
              const SizedBox(height: 16),
              Text('Payment Methods',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _paymentMethodOptions.map((method) {
                  final isSelected = _selectedPaymentMethods.contains(method);
                  return FilterChip(
                    label: Text(method),
                    selected: isSelected,
                    onSelected: (_isOwner || _shop == null)
                        ? (selected) {
                            setState(() {
                              if (selected) {
                                _selectedPaymentMethods.add(method);
                              } else {
                                _selectedPaymentMethods.remove(method);
                              }
                            });
                          }
                        : null,
                  );
                }).toList(),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Shipping Options
          _buildSection(
            theme,
            'Shipping',
            [
              Text('Shipping Options',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _shippingOptionsList.map((option) {
                  final isSelected = _selectedShippingOptions.contains(option);
                  return FilterChip(
                    label: Text(option),
                    selected: isSelected,
                    onSelected: (_isOwner || _shop == null)
                        ? (selected) {
                            setState(() {
                              if (selected) {
                                _selectedShippingOptions.add(option);
                              } else {
                                _selectedShippingOptions.remove(option);
                              }
                            });
                          }
                        : null,
                  );
                }).toList(),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Languages
          _buildSection(
            theme,
            'Languages',
            [
              Text('Supported Languages',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _supportedLanguages.map((lang) {
                  final isSelected = _selectedLanguages.contains(lang);
                  return FilterChip(
                    label: Text(lang),
                    selected: isSelected,
                    onSelected: (_isOwner || _shop == null)
                        ? (selected) {
                            setState(() {
                              if (selected) {
                                _selectedLanguages.add(lang);
                              } else {
                                _selectedLanguages.remove(lang);
                              }
                            });
                          }
                        : null,
                  );
                }).toList(),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Multilanguage Content
          if (_selectedLanguages.isNotEmpty) ...[
            _buildSection(
              theme,
              'Multilanguage Content',
              _selectedLanguages
                  .expand((lang) => [
                        const SizedBox(height: 16),
                        Text(
                          'Language: $lang',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _descriptionControllers[lang],
                          decoration: InputDecoration(
                            labelText: 'Description ($lang)',
                            hintText: 'Describe your shop',
                            border: const OutlineInputBorder(),
                          ),
                          enabled: _isOwner || _shop == null,
                          maxLines: 4,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _paymentInfoControllers[lang],
                          decoration: InputDecoration(
                            labelText: 'Payment Info ($lang)',
                            hintText: 'Payment instructions',
                            border: const OutlineInputBorder(),
                          ),
                          enabled: _isOwner || _shop == null,
                          maxLines: 4,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _shippingInfoControllers[lang],
                          decoration: InputDecoration(
                            labelText: 'Shipping Info ($lang)',
                            hintText: 'Shipping details and costs',
                            border: const OutlineInputBorder(),
                          ),
                          enabled: _isOwner || _shop == null,
                          maxLines: 4,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _returnPolicyControllers[lang],
                          decoration: InputDecoration(
                            labelText: 'Return Policy ($lang)',
                            hintText: 'Return and refund policy',
                            border: const OutlineInputBorder(),
                          ),
                          enabled: _isOwner || _shop == null,
                          maxLines: 4,
                        ),
                        const Divider(),
                      ])
                  .toList(),
            ),
          ],

          const SizedBox(height: 24),

          // Save button (bottom)
          if (_isOwner || _shop == null)
            FilledButton.icon(
              onPressed: _saveShop,
              icon: const Icon(Icons.save),
              label: const Text('Save Shop Settings'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// Build a section
  Widget _buildSection(ThemeData theme, String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  /// Show error message
  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  /// Show success message
  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}
