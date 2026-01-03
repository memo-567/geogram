/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../wallet/models/wallet_settings.dart';
import '../wallet/utils/default_terms.dart';
import '../services/i18n_service.dart';
import '../services/location_service.dart';
import '../widgets/wallet/currency_picker_widget.dart';

/// Wallet settings page for configuring default jurisdiction, currency, and terms.
class WalletSettingsPage extends StatefulWidget {
  final I18nService i18n;

  const WalletSettingsPage({
    super.key,
    required this.i18n,
  });

  @override
  State<WalletSettingsPage> createState() => _WalletSettingsPageState();
}

class _WalletSettingsPageState extends State<WalletSettingsPage> {
  final LocationService _locationService = LocationService();

  WalletSettings? _settings;
  List<String> _countries = [];
  bool _loading = true;
  bool _saving = false;
  bool _detectingLocation = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await WalletSettings.load();
    final countries = await _locationService.getAllCountries();

    if (mounted) {
      setState(() {
        _settings = settings;
        _countries = countries;
        _loading = false;
      });

      // Auto-detect jurisdiction if enabled and not already set
      if (settings.autoDetectJurisdiction &&
          (settings.defaultJurisdiction == null ||
              settings.defaultJurisdiction!.isEmpty)) {
        _detectLocation(silent: true);
      }
    }
  }

  Future<void> _detectLocation({bool silent = false}) async {
    setState(() => _detectingLocation = true);
    try {
      final geoResult = await _locationService.detectLocationViaIP();
      if (geoResult != null && geoResult.country != null && mounted) {
        // Find matching country in our list (case-insensitive)
        final matchedCountry = _countries.firstWhere(
          (c) => c.toLowerCase() == geoResult.country!.toLowerCase(),
          orElse: () => '',
        );

        if (matchedCountry.isNotEmpty) {
          setState(() {
            _settings = _settings?.copyWith(defaultJurisdiction: matchedCountry);
          });
          await _saveSettings(showNotification: !silent);
        }
      }
    } catch (e) {
      // Silently fail - user can select manually
    } finally {
      if (mounted) {
        setState(() => _detectingLocation = false);
      }
    }
  }

  Future<void> _saveSettings({bool showNotification = true}) async {
    if (_settings == null) return;
    setState(() => _saving = true);
    try {
      await _settings!.save();
      if (mounted && showNotification) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.i18n.t('wallet_settings_saved')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _selectCurrency() async {
    if (_settings == null) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => CurrencyPickerWidget(
        i18n: widget.i18n,
        selectedCurrency: _settings!.defaultCurrency,
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _settings = _settings!.copyWith(defaultCurrency: selected);
      });
      await _saveSettings();
    }
  }

  void _selectJurisdiction() async {
    if (_settings == null) return;

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _CountryPickerSheet(
        countries: _countries,
        selectedCountry: _settings!.defaultJurisdiction,
        i18n: widget.i18n,
        onDetectLocation: _detectLocation,
        isDetecting: _detectingLocation,
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _settings = _settings!.copyWith(defaultJurisdiction: result);
      });
      await _saveSettings();
    }
  }

  void _showTermsPreview() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          final theme = Theme.of(context);
          return Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.gavel,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      widget.i18n.t('wallet_terms_title'),
                      style: theme.textTheme.titleLarge,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Terms content
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Short summary
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Summary',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              DefaultTerms.getShortTermsSummary(),
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Full terms sections
                      _buildTermsSection(theme, '1', widget.i18n.t('wallet_terms_1_title'), [
                        widget.i18n.t('wallet_terms_1_1'),
                        widget.i18n.t('wallet_terms_1_1_us'),
                        widget.i18n.t('wallet_terms_1_1_eu'),
                        widget.i18n.t('wallet_terms_1_2'),
                        widget.i18n.t('wallet_terms_1_3'),
                      ]),
                      _buildTermsSection(theme, '2', widget.i18n.t('wallet_terms_2_title'), [
                        widget.i18n.t('wallet_terms_2_1'),
                        widget.i18n.t('wallet_terms_2_2'),
                      ]),
                      _buildTermsSection(theme, '3', widget.i18n.t('wallet_terms_3_title'), [
                        widget.i18n.t('wallet_terms_3_1'),
                        widget.i18n.t('wallet_terms_3_2'),
                      ]),
                      _buildTermsSection(theme, '4', widget.i18n.t('wallet_terms_4_title'), [
                        widget.i18n.t('wallet_terms_4_1'),
                        widget.i18n.t('wallet_terms_4_2'),
                        widget.i18n.t('wallet_terms_4_3'),
                      ]),
                      _buildTermsSection(theme, '5', widget.i18n.t('wallet_terms_5_title'), [
                        widget.i18n.t('wallet_terms_5_1'),
                        widget.i18n.t('wallet_terms_5_2'),
                        widget.i18n.t('wallet_terms_5_3'),
                      ]),
                      _buildTermsSection(theme, '6', widget.i18n.t('wallet_terms_6_title'), [
                        widget.i18n.t('wallet_terms_6_1'),
                        widget.i18n.t('wallet_terms_6_2'),
                      ]),
                      _buildTermsSection(theme, '7', widget.i18n.t('wallet_terms_7_title'), [
                        widget.i18n.t('wallet_terms_7_1'),
                        widget.i18n.t('wallet_terms_7_2'),
                        widget.i18n.t('wallet_terms_7_3'),
                      ]),
                      _buildTermsSection(theme, '8', widget.i18n.t('wallet_terms_8_title'), [
                        widget.i18n.t('wallet_terms_8_1', params: [_settings?.defaultJurisdiction ?? 'the jurisdiction where the creditor resides']),
                        widget.i18n.t('wallet_terms_8_2'),
                      ]),
                      _buildTermsSection(theme, '9', widget.i18n.t('wallet_terms_9_title'), [
                        widget.i18n.t('wallet_terms_9_1'),
                      ]),
                      _buildTermsSection(theme, '10', widget.i18n.t('wallet_terms_10_title'), [
                        widget.i18n.t('wallet_terms_10_1'),
                        widget.i18n.t('wallet_terms_10_2'),
                      ]),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTermsSection(ThemeData theme, String number, String title, List<String> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  item,
                  style: theme.textTheme.bodySmall,
                ),
              )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.i18n.t('wallet_settings_title')),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.i18n.t('wallet_settings_title')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Jurisdiction section
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.gavel),
                  title: Text(widget.i18n.t('wallet_settings_default_jurisdiction')),
                  subtitle: Text(
                    _settings?.defaultJurisdiction?.isNotEmpty == true
                        ? _settings!.defaultJurisdiction!
                        : widget.i18n.t('wallet_settings_default_jurisdiction_desc'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _selectJurisdiction,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: _detectingLocation
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                  title: Text(widget.i18n.t('wallet_settings_detect_location')),
                  subtitle: Text(widget.i18n.t('wallet_settings_detect_location_hint')),
                  enabled: !_detectingLocation,
                  onTap: _detectingLocation ? null : _detectLocation,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Currency section
          Card(
            child: ListTile(
              leading: const Icon(Icons.attach_money),
              title: Text(widget.i18n.t('wallet_settings_default_currency')),
              subtitle: Text(_settings?.defaultCurrency ?? 'EUR'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _selectCurrency,
            ),
          ),
          const SizedBox(height: 16),

          // Terms preview section
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.description),
                  title: Text(widget.i18n.t('wallet_include_terms')),
                  subtitle: Text(widget.i18n.t('wallet_include_terms_hint')),
                  value: _settings?.includeTermsByDefault ?? true,
                  onChanged: (value) {
                    setState(() {
                      _settings = _settings?.copyWith(includeTermsByDefault: value);
                    });
                    _saveSettings();
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.edit_note),
                  title: Text(widget.i18n.t('wallet_include_custom_terms')),
                  subtitle: Text(widget.i18n.t('wallet_include_custom_terms_hint')),
                  value: _settings?.includeCustomTermsByDefault ?? false,
                  onChanged: (value) {
                    setState(() {
                      _settings = _settings?.copyWith(includeCustomTermsByDefault: value);
                    });
                    _saveSettings();
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.visibility),
                  title: Text(widget.i18n.t('wallet_settings_terms_preview')),
                  subtitle: Text(
                    widget.i18n.t('wallet_settings_terms_preview_desc'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showTermsPreview,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: Text(widget.i18n.t('wallet_settings_custom_terms')),
                  subtitle: Text(
                    _settings?.defaultCustomTerms?.isNotEmpty == true
                        ? _settings!.defaultCustomTerms!.length > 50
                            ? '${_settings!.defaultCustomTerms!.substring(0, 50)}...'
                            : _settings!.defaultCustomTerms!
                        : widget.i18n.t('wallet_settings_custom_terms_hint'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _editCustomTerms,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Interest section
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.percent),
                  title: Text(widget.i18n.t('wallet_settings_interest_rate')),
                  subtitle: Text(
                    _settings?.defaultInterestRate != null
                        ? '${_settings!.defaultInterestRate!.toStringAsFixed(2)}% / year'
                        : 'Not set',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _selectInterestRate,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.calendar_today),
                  title: Text(widget.i18n.t('wallet_settings_payment_frequency')),
                  subtitle: Text(
                    _settings?.defaultPaymentFrequency.displayName ?? 'Monthly',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: DropdownButton<PaymentFrequency>(
                    value: _settings?.defaultPaymentFrequency ?? PaymentFrequency.monthly,
                    underline: const SizedBox(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _settings = _settings?.copyWith(defaultPaymentFrequency: value);
                        });
                        _saveSettings();
                      }
                    },
                    items: PaymentFrequency.values
                        .where((f) => f != PaymentFrequency.custom)
                        .map((f) => DropdownMenuItem(
                              value: f,
                              child: Text(f.displayName),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _selectInterestRate() async {
    if (_settings == null) return;
    final controller = TextEditingController(
      text: _settings!.defaultInterestRate?.toString() ?? '',
    );

    final result = await showDialog<double?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.i18n.t('wallet_settings_interest_rate')),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: widget.i18n.t('wallet_interest_rate'),
            suffixText: '% / year',
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(widget.i18n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 0.0),
            child: Text(widget.i18n.t('clear')),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(controller.text);
              Navigator.pop(context, value);
            },
            child: Text(widget.i18n.t('save')),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _settings = _settings!.copyWith(
          defaultInterestRate: result > 0 ? result : null,
        );
      });
      await _saveSettings();
    }
  }

  void _editCustomTerms() async {
    if (_settings == null) return;
    final controller = TextEditingController(
      text: _settings!.defaultCustomTerms ?? '',
    );

    final result = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            final theme = Theme.of(context);
            return Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Title
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.edit_note, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.i18n.t('wallet_settings_custom_terms'),
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    widget.i18n.t('wallet_settings_custom_terms_desc'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                // Text field
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: controller,
                      maxLines: null,
                      minLines: 10,
                      decoration: InputDecoration(
                        hintText: widget.i18n.t('wallet_settings_custom_terms_placeholder'),
                        border: const OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      textInputAction: TextInputAction.newline,
                    ),
                  ),
                ),
                // Actions
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          controller.clear();
                          Navigator.pop(context, '');
                        },
                        child: Text(widget.i18n.t('clear')),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(widget.i18n.t('cancel')),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, controller.text),
                        child: Text(widget.i18n.t('save')),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        if (result.isEmpty) {
          _settings = _settings!.copyWith(clearCustomTerms: true);
        } else {
          _settings = _settings!.copyWith(defaultCustomTerms: result);
        }
      });
      await _saveSettings();
    }
  }
}

/// Bottom sheet for selecting a country with search
class _CountryPickerSheet extends StatefulWidget {
  final List<String> countries;
  final String? selectedCountry;
  final I18nService i18n;
  final VoidCallback onDetectLocation;
  final bool isDetecting;

  const _CountryPickerSheet({
    required this.countries,
    required this.selectedCountry,
    required this.i18n,
    required this.onDetectLocation,
    required this.isDetecting,
  });

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _filteredCountries = [];

  @override
  void initState() {
    super.initState();
    _filteredCountries = widget.countries;
    _searchController.addListener(_filterCountries);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterCountries() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredCountries = widget.countries;
      } else {
        _filteredCountries = widget.countries
            .where((c) => c.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title and search
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.public, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      widget.i18n.t('wallet_settings_select_country'),
                      style: theme.textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: widget.i18n.t('search'),
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  autofocus: true,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Country list
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: _filteredCountries.length,
              itemBuilder: (context, index) {
                final country = _filteredCountries[index];
                final isSelected = country == widget.selectedCountry;

                return ListTile(
                  title: Text(country),
                  trailing: isSelected
                      ? Icon(Icons.check, color: theme.colorScheme.primary)
                      : null,
                  selected: isSelected,
                  onTap: () => Navigator.pop(context, country),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
