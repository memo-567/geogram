/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Currency picker widget for selecting currencies.
library;

import 'package:flutter/material.dart';

import '../../wallet/models/currency.dart';
import '../../services/i18n_service.dart';

/// Widget for picking a currency from the available currencies
class CurrencyPickerWidget extends StatefulWidget {
  final I18nService i18n;
  final String? selectedCurrency;
  final bool showTime;
  final bool showCrypto;
  final bool showFiat;
  final bool showCustom;

  const CurrencyPickerWidget({
    super.key,
    required this.i18n,
    this.selectedCurrency,
    this.showTime = true,
    this.showCrypto = true,
    this.showFiat = true,
    this.showCustom = true,
  });

  @override
  State<CurrencyPickerWidget> createState() => _CurrencyPickerWidgetState();
}

class _CurrencyPickerWidgetState extends State<CurrencyPickerWidget> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Currency> get _filteredCurrencies {
    var currencies = <Currency>[];

    if (widget.showTime) {
      currencies.add(Currencies.min);
    }
    if (widget.showCrypto) {
      currencies.addAll(Currencies.crypto);
    }
    if (widget.showFiat) {
      currencies.addAll(Currencies.fiat);
    }
    if (widget.showCustom) {
      currencies.addAll(Currencies.custom);
    }

    if (_searchQuery.isEmpty) {
      return currencies;
    }

    final query = _searchQuery.toLowerCase();
    return currencies.where((c) {
      return c.code.toLowerCase().contains(query) ||
          c.name.toLowerCase().contains(query);
    }).toList();
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
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.i18n.t('wallet_select_currency'),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                // Search
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: widget.i18n.t('search'),
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Currency list
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: _filteredCurrencies.length,
              itemBuilder: (context, index) {
                final currency = _filteredCurrencies[index];
                final isSelected = currency.code == widget.selectedCurrency;

                // Section headers
                Widget? header;
                if (index == 0 && currency.isTime) {
                  header = _buildSectionHeader(widget.i18n.t('wallet_currency_time'));
                } else if (currency.isCrypto &&
                    (index == 0 || !_filteredCurrencies[index - 1].isCrypto)) {
                  header = _buildSectionHeader(widget.i18n.t('wallet_currency_crypto'));
                } else if (!currency.isCrypto &&
                    !currency.isTime &&
                    !currency.isCustom &&
                    (index == 0 ||
                        _filteredCurrencies[index - 1].isCrypto ||
                        _filteredCurrencies[index - 1].isTime)) {
                  header = _buildSectionHeader(widget.i18n.t('wallet_currency_fiat'));
                } else if (currency.isCustom &&
                    (index == 0 || !_filteredCurrencies[index - 1].isCustom)) {
                  header = _buildSectionHeader(widget.i18n.t('wallet_currency_custom'));
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (header != null) header,
                    ListTile(
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _getCurrencyColor(currency).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            currency.symbol.trim().isEmpty
                                ? currency.code.substring(0, currency.code.length > 2 ? 2 : currency.code.length)
                                : currency.symbol.trim(),
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: _getCurrencyColor(currency),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      title: Text(currency.name),
                      subtitle: Text(currency.code),
                      trailing: isSelected
                          ? Icon(
                              Icons.check_circle,
                              color: theme.colorScheme.primary,
                            )
                          : null,
                      onTap: () => Navigator.pop(context, currency.code),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getCurrencyColor(Currency currency) {
    if (currency.isTime) {
      return Colors.purple;
    } else if (currency.isCrypto) {
      return Colors.orange;
    } else if (currency.isCustom) {
      return Colors.teal;
    } else {
      return Colors.blue;
    }
  }
}
