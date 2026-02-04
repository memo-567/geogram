/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../wallet/models/debt_ledger.dart';
import '../wallet/services/wallet_service.dart';
import '../services/i18n_service.dart';

/// Page to view the raw contract document with markdown rendering.
class ContractDocumentPage extends StatefulWidget {
  final String appPath;
  final String debtId;
  final I18nService i18n;

  const ContractDocumentPage({
    super.key,
    required this.appPath,
    required this.debtId,
    required this.i18n,
  });

  @override
  State<ContractDocumentPage> createState() => _ContractDocumentPageState();
}

class _ContractDocumentPageState extends State<ContractDocumentPage> {
  final WalletService _service = WalletService();

  String? _contractContent;
  bool _loading = true;
  DebtLedger? _ledger;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    setState(() => _loading = true);
    try {
      await _service.initializeApp(widget.appPath);
      final ledger = await _service.findDebt(widget.debtId);

      if (ledger != null) {
        // Verify signatures
        await _service.verifyDebt(ledger);
      }

      setState(() {
        _ledger = ledger;
        _contractContent = ledger?.export();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.i18n.t('wallet_document_title'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_contractContent == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.i18n.t('wallet_document_title'))),
        body: Center(
          child: Text(widget.i18n.t('wallet_debt_not_found')),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.i18n.t('wallet_document_title')),
        actions: [
          // Signature status indicators
          if (_ledger != null) ...[
            _buildSignatureChip(
              theme,
              widget.i18n.t('wallet_creditor'),
              _ledger!.hasValidCreate,
            ),
            const SizedBox(width: 8),
            _buildSignatureChip(
              theme,
              widget.i18n.t('wallet_debtor'),
              _ledger!.hasValidConfirm,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Markdown(
            data: _contractContent!,
            padding: const EdgeInsets.all(16),
            selectable: true,
            styleSheet: MarkdownStyleSheet(
              h1: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              h2: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              p: theme.textTheme.bodyMedium,
              blockquote: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              blockquoteDecoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 4,
                  ),
                ),
              ),
              code: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
              codeblockDecoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSignatureChip(ThemeData theme, String label, bool isSigned) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isSigned
            ? Colors.green.withValues(alpha: 0.15)
            : Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSigned ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 14,
            color: isSigned ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isSigned ? Colors.green : Colors.orange,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
