/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../wallet/models/wallet_settings.dart';
import '../wallet/services/wallet_service.dart';
import '../services/i18n_service.dart';
import '../services/profile_service.dart';
import '../widgets/wallet/currency_picker_widget.dart';
import '../widgets/user_picker_widget.dart';

/// Page for creating a new debt
class CreateDebtPage extends StatefulWidget {
  final String appPath;
  final I18nService i18n;

  const CreateDebtPage({
    super.key,
    required this.appPath,
    required this.i18n,
  });

  @override
  State<CreateDebtPage> createState() => _CreateDebtPageState();
}

class _CreateDebtPageState extends State<CreateDebtPage> {
  final _formKey = GlobalKey<FormState>();
  final WalletService _walletService = WalletService();
  final ProfileService _profileService = ProfileService();
  final ImagePicker _imagePicker = ImagePicker();

  // Form controllers
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _counterpartyController = TextEditingController();
  final _termsController = TextEditingController();
  final _interestRateController = TextEditingController();
  final _installmentsController = TextEditingController(text: '1');

  // Form state
  String _currency = 'EUR';
  bool _isCreditor = true; // true = they owe me, false = I owe them
  DateTime? _dueDate;
  bool _hasInterest = false;
  PaymentFrequency _paymentFrequency = PaymentFrequency.monthly;
  bool _includeTerms = true;
  bool _loading = false;

  // Selected counterparty info
  String? _counterpartyNpub;
  String? _counterpartyDisplayName;

  // Attachments
  final List<XFile> _attachments = [];

  WalletSettings? _settings;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _counterpartyController.dispose();
    _termsController.dispose();
    _interestRateController.dispose();
    _installmentsController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await WalletSettings.load();
    setState(() {
      _settings = settings;
      _currency = settings.defaultCurrency;
      _includeTerms = settings.includeTermsByDefault;
      _paymentFrequency = settings.defaultPaymentFrequency;
      if (settings.defaultInterestRate != null && settings.defaultInterestRate! > 0) {
        _hasInterest = true;
        _interestRateController.text = settings.defaultInterestRate!.toString();
      }
    });
  }

  Future<void> _selectDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  void _selectCurrency() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => CurrencyPickerWidget(
        i18n: widget.i18n,
        selectedCurrency: _currency,
      ),
    );
    if (selected != null) {
      setState(() => _currency = selected);
    }
  }

  Future<void> _createDebt() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate that a user has been selected
    if (_counterpartyNpub == null || _counterpartyNpub!.isEmpty) {
      _showError(widget.i18n.t('wallet_select_user'));
      return;
    }

    setState(() => _loading = true);

    try {
      final profile = _profileService.getProfile();

      final amount = double.parse(_amountController.text);
      final description = _descriptionController.text;
      final counterparty = _counterpartyController.text;
      final counterpartyNpub = _counterpartyNpub ?? '';

      // Determine creditor/debtor based on role
      final String creditor;
      final String creditorNpub;
      final String? creditorName;
      final String debtor;
      final String debtorNpub;
      final String? debtorName;

      if (_isCreditor) {
        // I am the creditor (they owe me)
        creditor = profile.callsign;
        creditorNpub = profile.npub;
        creditorName = profile.displayName;
        debtor = counterparty;
        debtorNpub = counterpartyNpub;
        debtorName = counterparty;
      } else {
        // I am the debtor (I owe them)
        creditor = counterparty;
        creditorNpub = counterpartyNpub;
        creditorName = counterparty;
        debtor = profile.callsign;
        debtorNpub = profile.npub;
        debtorName = profile.displayName;
      }

      final debt = await _walletService.createDebt(
        description: description,
        creditor: creditor,
        creditorNpub: creditorNpub,
        creditorName: creditorName,
        debtor: debtor,
        debtorNpub: debtorNpub,
        debtorName: debtorName,
        amount: amount,
        currency: _currency,
        dueDate: _dueDate?.toIso8601String().substring(0, 10),
        terms: _termsController.text.isNotEmpty ? _termsController.text : null,
        includeTerms: _includeTerms,
        governingJurisdiction: _settings?.defaultJurisdiction,
        annualInterestRate: _hasInterest
            ? double.tryParse(_interestRateController.text)
            : null,
        numberOfInstallments: int.tryParse(_installmentsController.text) ?? 1,
        paymentIntervalDays: _paymentFrequency.daysInterval,
        profile: profile,
      );

      if (debt != null && mounted) {
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

  Future<void> _pickImageFromCamera() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (image != null && mounted) {
        setState(() => _attachments.add(image));
      }
    } catch (e) {
      _showError(widget.i18n.t('wallet_photo_error'));
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final List<XFile> images = await _imagePicker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (images.isNotEmpty && mounted) {
        setState(() => _attachments.addAll(images));
      }
    } catch (e) {
      _showError(widget.i18n.t('wallet_photo_error'));
    }
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  /// Camera is only supported on mobile platforms and web
  bool get _isCameraSupported {
    if (kIsWeb) return true;
    return Platform.isAndroid || Platform.isIOS;
  }

  void _showAttachmentOptions() {
    final theme = Theme.of(context);

    // On desktop, go directly to gallery since camera isn't supported
    if (!_isCameraSupported) {
      _pickImageFromGallery();
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                widget.i18n.t('wallet_add_photo'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(widget.i18n.t('wallet_take_photo')),
              onTap: () {
                Navigator.pop(context);
                _pickImageFromCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(widget.i18n.t('wallet_choose_from_gallery')),
              onTap: () {
                Navigator.pop(context);
                _pickImageFromGallery();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Show user picker to select a counterparty
  Future<void> _showUserPicker() async {
    final profile = _profileService.getProfile();

    final selected = await showModalBottomSheet<UserPickerResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => UserPickerWidget(
        i18n: widget.i18n,
        excludeNpub: profile.npub, // Exclude current user
      ),
    );

    if (selected != null && mounted) {
      setState(() {
        _counterpartyController.text = selected.callsign;
        _counterpartyNpub = selected.npub;
        _counterpartyDisplayName = selected.displayName;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.i18n.t('wallet_create_debt')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Direction selector (who owes who)
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
                          label: Text(widget.i18n.t('wallet_they_owe_me')),
                          icon: const Icon(Icons.arrow_downward),
                        ),
                        ButtonSegment(
                          value: false,
                          label: Text(widget.i18n.t('wallet_i_owe_them')),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                      ],
                      selected: {_isCreditor},
                      onSelectionChanged: (value) {
                        setState(() => _isCreditor = value.first);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Counterparty section with user picker
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.i18n.t('wallet_other_person'),
                          style: theme.textTheme.titleSmall,
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: _showUserPicker,
                          icon: const Icon(Icons.person_search),
                          label: Text(widget.i18n.t('wallet_select_user')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Selected user display
                    if (_counterpartyNpub != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: theme.colorScheme.primaryContainer,
                              child: Text(
                                _counterpartyController.text.isNotEmpty
                                    ? _counterpartyController.text[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: theme.colorScheme.onPrimaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _counterpartyDisplayName ?? _counterpartyController.text,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                  Text(
                                    _counterpartyController.text,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  _counterpartyController.clear();
                                  _counterpartyNpub = null;
                                  _counterpartyDisplayName = null;
                                });
                              },
                              icon: const Icon(Icons.close),
                              tooltip: widget.i18n.t('clear'),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // Empty state - prompt to select a user
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                widget.i18n.t('wallet_counterparty_hint'),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
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
                      labelText: widget.i18n.t('wallet_amount'),
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
                        labelText: widget.i18n.t('wallet_currency'),
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
                labelText: widget.i18n.t('wallet_description'),
                hintText: widget.i18n.t('wallet_description_hint'),
                prefixIcon: const Icon(Icons.description),
                border: const OutlineInputBorder(),
              ),
              maxLines: 3,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return widget.i18n.t('required');
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Due date
            InkWell(
              onTap: _selectDueDate,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: widget.i18n.t('wallet_due_date'),
                  prefixIcon: const Icon(Icons.event),
                  border: const OutlineInputBorder(),
                  suffixIcon: _dueDate != null
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _dueDate = null),
                        )
                      : null,
                ),
                child: Text(
                  _dueDate != null
                      ? '${_dueDate!.year}-${_dueDate!.month.toString().padLeft(2, '0')}-${_dueDate!.day.toString().padLeft(2, '0')}'
                      : widget.i18n.t('wallet_no_due_date'),
                  style: TextStyle(
                    color: _dueDate != null
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Interest section
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text(widget.i18n.t('wallet_has_interest')),
                    subtitle: Text(widget.i18n.t('wallet_has_interest_hint')),
                    value: _hasInterest,
                    onChanged: (value) => setState(() => _hasInterest = value),
                  ),
                  if (_hasInterest) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // Interest rate
                          TextFormField(
                            controller: _interestRateController,
                            decoration: InputDecoration(
                              labelText: widget.i18n.t('wallet_interest_rate'),
                              suffixText: '% / year',
                              border: const OutlineInputBorder(),
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Number of installments
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _installmentsController,
                                  decoration: InputDecoration(
                                    labelText: widget.i18n.t('wallet_installments'),
                                    border: const OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: DropdownButtonFormField<PaymentFrequency>(
                                  value: _paymentFrequency,
                                  decoration: InputDecoration(
                                    labelText: widget.i18n.t('wallet_frequency'),
                                    border: const OutlineInputBorder(),
                                  ),
                                  items: PaymentFrequency.values
                                      .where((f) => f != PaymentFrequency.custom)
                                      .map((f) => DropdownMenuItem(
                                            value: f,
                                            child: Text(f.displayName),
                                          ))
                                      .toList(),
                                  onChanged: (value) {
                                    if (value != null) {
                                      setState(() => _paymentFrequency = value);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Terms section
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text(widget.i18n.t('wallet_include_terms')),
                    subtitle: Text(widget.i18n.t('wallet_include_terms_hint')),
                    value: _includeTerms,
                    onChanged: (value) => setState(() => _includeTerms = value),
                  ),
                  if (_includeTerms) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextFormField(
                        controller: _termsController,
                        decoration: InputDecoration(
                          labelText: widget.i18n.t('wallet_additional_terms'),
                          hintText: widget.i18n.t('wallet_additional_terms_hint'),
                          border: const OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Attachments section
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.i18n.t('wallet_attachments'),
                              style: theme.textTheme.titleSmall,
                            ),
                            Text(
                              widget.i18n.t('wallet_attachments_hint'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            if (_isCameraSupported)
                              IconButton(
                                onPressed: _pickImageFromCamera,
                                icon: const Icon(Icons.camera_alt),
                                tooltip: widget.i18n.t('wallet_take_photo'),
                              ),
                            IconButton(
                              onPressed: _pickImageFromGallery,
                              icon: const Icon(Icons.photo_library),
                              tooltip: widget.i18n.t('wallet_choose_from_gallery'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_attachments.isNotEmpty) ...[
                    const Divider(height: 1),
                    SizedBox(
                      height: 120,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.all(12),
                        itemCount: _attachments.length,
                        itemBuilder: (context, index) {
                          final file = _attachments[index];
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(file.path),
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const SizedBox(
                                        width: 100,
                                        height: 100,
                                        child: Icon(Icons.broken_image, color: Colors.grey),
                                      );
                                    },
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: () => _removeAttachment(index),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.6),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 80), // Space for FAB
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _createDebt,
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
        icon: _loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.onPrimary,
                ),
              )
            : const Icon(Icons.check),
        label: Text(widget.i18n.t('create')),
      ),
    );
  }
}
