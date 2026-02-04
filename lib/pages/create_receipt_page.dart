/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../wallet/models/receipt.dart';
import '../wallet/services/wallet_service.dart';
import '../services/i18n_service.dart';
import '../services/profile_service.dart';
import '../widgets/wallet/currency_picker_widget.dart';

/// Page for creating a new payment receipt
class CreateReceiptPage extends StatefulWidget {
  final String appPath;
  final I18nService i18n;

  const CreateReceiptPage({
    super.key,
    required this.appPath,
    required this.i18n,
  });

  @override
  State<CreateReceiptPage> createState() => _CreateReceiptPageState();
}

class _CreateReceiptPageState extends State<CreateReceiptPage> {
  final _formKey = GlobalKey<FormState>();
  final WalletService _walletService = WalletService();
  final ProfileService _profileService = ProfileService();

  // Form controllers
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _counterpartyController = TextEditingController();
  final _counterpartyNpubController = TextEditingController();
  final _notesController = TextEditingController();
  final _referenceController = TextEditingController();

  // Form state
  String _currency = 'EUR';
  bool _isPayer = true; // true = I paid, false = I received
  String _paymentMethod = PaymentMethods.cash;
  bool _useCurrentLocation = false;
  ReceiptLocation? _location;
  bool _loading = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _counterpartyController.dispose();
    _counterpartyNpubController.dispose();
    _notesController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  void _selectCurrency() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => CurrencyPickerWidget(
        i18n: widget.i18n,
        selectedCurrency: _currency,
        showTime: false, // Receipts are for monetary payments
      ),
    );
    if (selected != null) {
      setState(() => _currency = selected);
    }
  }

  Future<void> _createReceipt() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      final profile = _profileService.getProfile();

      final amount = double.parse(_amountController.text);
      final description = _descriptionController.text;
      final counterparty = _counterpartyController.text;
      final counterpartyNpub = _counterpartyNpubController.text;

      // Determine payer/payee based on role
      final String payer;
      final String payerNpub;
      final String? payerName;
      final String payee;
      final String payeeNpub;
      final String? payeeName;

      if (_isPayer) {
        // I am the payer (I paid them)
        payer = profile.callsign;
        payerNpub = profile.npub;
        payerName = profile.displayName;
        payee = counterparty;
        payeeNpub = counterpartyNpub;
        payeeName = counterparty;
      } else {
        // I am the payee (they paid me)
        payer = counterparty;
        payerNpub = counterpartyNpub;
        payerName = counterparty;
        payee = profile.callsign;
        payeeNpub = profile.npub;
        payeeName = profile.displayName;
      }

      final receipt = await _walletService.createReceipt(
        description: description,
        payer: payer,
        payerNpub: payerNpub,
        payerName: payerName,
        payee: payee,
        payeeNpub: payeeNpub,
        payeeName: payeeName,
        amount: amount,
        currency: _currency,
        notes: _notesController.text.isNotEmpty ? _notesController.text : null,
        paymentMethod: _paymentMethod,
        reference: _referenceController.text.isNotEmpty ? _referenceController.text : null,
        location: _location,
        profile: profile,
      );

      if (receipt != null && mounted) {
        Navigator.pop(context, true);
      } else {
        _showError(widget.i18n.t('wallet_create_error'));
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _getPaymentMethodLabel(String method) {
    final key = 'wallet_receipt_payment_$method';
    final translated = widget.i18n.t(key);
    // If translation key is returned, use display name
    if (translated == key) {
      return PaymentMethods.displayName(method);
    }
    return translated;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.i18n.t('wallet_receipt_create')),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _createReceipt,
              child: Text(widget.i18n.t('create')),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Direction selector (who paid who)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.i18n.t('wallet_direction'),
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: true,
                          label: Text(widget.i18n.t('wallet_i_paid')),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        ButtonSegment(
                          value: false,
                          label: Text(widget.i18n.t('wallet_i_received')),
                          icon: const Icon(Icons.arrow_downward),
                        ),
                      ],
                      selected: {_isPayer},
                      onSelectionChanged: (value) {
                        setState(() => _isPayer = value.first);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Counterparty
            TextFormField(
              controller: _counterpartyController,
              decoration: InputDecoration(
                labelText: _isPayer
                    ? widget.i18n.t('wallet_receipt_payee')
                    : widget.i18n.t('wallet_receipt_payer'),
                hintText: widget.i18n.t('wallet_counterparty_hint'),
                prefixIcon: const Icon(Icons.person),
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return widget.i18n.t('required');
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Counterparty npub
            TextFormField(
              controller: _counterpartyNpubController,
              decoration: InputDecoration(
                labelText: widget.i18n.t('wallet_counterparty_npub'),
                hintText: 'npub1...',
                prefixIcon: const Icon(Icons.key),
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return widget.i18n.t('required');
                }
                if (!value.startsWith('npub1')) {
                  return widget.i18n.t('wallet_invalid_npub');
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Amount and currency
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _amountController,
                    decoration: InputDecoration(
                      labelText: widget.i18n.t('wallet_receipt_amount'),
                      prefixIcon: const Icon(Icons.attach_money),
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,8}')),
                    ],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return widget.i18n.t('required');
                      }
                      final amount = double.tryParse(value);
                      if (amount == null || amount <= 0) {
                        return widget.i18n.t('wallet_invalid_amount');
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: _selectCurrency,
                    borderRadius: BorderRadius.circular(4),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: widget.i18n.t('wallet_receipt_currency'),
                        border: const OutlineInputBorder(),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_currency),
                          const Icon(Icons.arrow_drop_down),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Description
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: widget.i18n.t('wallet_receipt_description'),
                hintText: widget.i18n.t('wallet_receipt_description_hint'),
                prefixIcon: const Icon(Icons.description),
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return widget.i18n.t('required');
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Payment method
            DropdownButtonFormField<String>(
              value: _paymentMethod,
              decoration: InputDecoration(
                labelText: widget.i18n.t('wallet_receipt_payment_method'),
                prefixIcon: const Icon(Icons.payment),
                border: const OutlineInputBorder(),
              ),
              items: PaymentMethods.all
                  .map((method) => DropdownMenuItem(
                        value: method,
                        child: Text(_getPaymentMethodLabel(method)),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _paymentMethod = value);
                }
              },
            ),
            const SizedBox(height: 16),

            // Reference (optional)
            TextFormField(
              controller: _referenceController,
              decoration: InputDecoration(
                labelText: widget.i18n.t('wallet_receipt_reference'),
                hintText: widget.i18n.t('wallet_receipt_reference_hint'),
                prefixIcon: const Icon(Icons.tag),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Notes (optional)
            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: widget.i18n.t('wallet_receipt_notes'),
                prefixIcon: const Icon(Icons.note),
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // Location
            Card(
              child: SwitchListTile(
                title: Text(widget.i18n.t('wallet_receipt_location')),
                subtitle: Text(widget.i18n.t('wallet_receipt_location_current')),
                secondary: const Icon(Icons.location_on),
                value: _useCurrentLocation,
                onChanged: (value) async {
                  setState(() => _useCurrentLocation = value);
                  if (value) {
                    // TODO: Get current location
                    // For now, just show that location will be captured
                  } else {
                    _location = null;
                  }
                },
              ),
            ),
            const SizedBox(height: 80), // Space for FAB
          ],
        ),
      ),
    );
  }
}
