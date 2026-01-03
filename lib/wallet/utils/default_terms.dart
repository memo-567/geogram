/// Default terms and conditions for debt contracts.
///
/// These terms are designed to meet legal requirements in both
/// the United States (E-SIGN Act, UETA) and European Union (eIDAS).
///
/// Terms are generated in both English (as international baseline)
/// and the user's selected language for accessibility.
library;

import '../../services/i18n_service.dart';
import '../models/payment_schedule.dart';

/// Provides default legal terms for debt contracts.
class DefaultTerms {
  DefaultTerms._();

  /// Build the full content for a create entry including terms.
  ///
  /// Generates bilingual terms if the user's language is not English.
  /// English is always included as the international legal baseline.
  static String buildCreateContent({
    required String description,
    String? additionalTerms,
    String? governingJurisdiction,
    PaymentSchedule? paymentSchedule,
  }) {
    final buffer = StringBuffer();
    final i18n = I18nService();
    final currentLang = i18n.currentLanguage;
    final isEnglish = currentLang.startsWith('en');

    // User's description
    buffer.writeln(description);

    // Payment schedule if provided
    if (paymentSchedule != null) {
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln();
      buffer.write(_buildPaymentSchedule(paymentSchedule, 'en_US'));
      if (!isEnglish) {
        buffer.writeln();
        buffer.writeln('---');
        buffer.writeln();
        buffer.write(_buildPaymentSchedule(paymentSchedule, currentLang));
      }
    }

    // Terms reference
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_reference', 'en_US'));
    if (!isEnglish) {
      buffer.writeln();
      buffer.writeln(_t('wallet_terms_reference', currentLang));
    }

    // Full terms - English first (international baseline)
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();
    buffer.writeln('# TERMS AND CONDITIONS (ENGLISH)');
    buffer.writeln();
    buffer.write(_buildTerms(
      governingJurisdiction: governingJurisdiction,
      paymentSchedule: paymentSchedule,
      language: 'en_US',
    ));

    // Terms in user's language if not English
    if (!isEnglish) {
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln();
      buffer.writeln('# ${_getTermsTitleInLanguage(currentLang)}');
      buffer.writeln();
      buffer.write(_buildTerms(
        governingJurisdiction: governingJurisdiction,
        paymentSchedule: paymentSchedule,
        language: currentLang,
      ));
    }

    // Additional custom terms if provided
    if (additionalTerms != null && additionalTerms.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln();
      buffer.writeln('## Additional Terms / Termos Adicionais');
      buffer.writeln();
      buffer.writeln(additionalTerms);
    }

    return buffer.toString();
  }

  /// Get the terms title in the specified language.
  static String _getTermsTitleInLanguage(String language) {
    switch (language) {
      case 'pt_PT':
        return 'TERMOS E CONDIÇÕES (PORTUGUÊS)';
      default:
        return 'TERMS AND CONDITIONS';
    }
  }

  /// Build the payment schedule in the specified language.
  static String _buildPaymentSchedule(PaymentSchedule schedule, String language) {
    final buffer = StringBuffer();

    buffer.writeln('## ${_t('wallet_payment_schedule', language)}');
    buffer.writeln();
    buffer.writeln('| ${_t('wallet_payment_number', language)} '
        '| ${_t('wallet_payment_due_date', language)} '
        '| ${_t('wallet_payment_principal', language)} '
        '| ${_t('wallet_payment_interest', language)} '
        '| ${_t('wallet_payment_total', language)} '
        '| ${_t('wallet_payment_remaining', language)} |');
    buffer.writeln('|---|----------|-----------|----------|-------|-----------|');

    for (final installment in schedule.installments) {
      buffer.writeln(
        '| ${installment.number} '
        '| ${installment.formattedDueDate} '
        '| ${schedule.formatAmount(installment.principal)} '
        '| ${schedule.formatAmount(installment.interest)} '
        '| ${schedule.formatAmount(installment.total)} '
        '| ${schedule.formatAmount(installment.remainingBalance)} |',
      );
    }

    buffer.writeln();
    buffer.writeln('**${_t('wallet_payment_summary', language)}:**');
    buffer.writeln('- ${_t('wallet_payment_principal_label', language)}: ${schedule.formatAmount(schedule.principal)}');
    if (schedule.annualInterestRate > 0) {
      buffer.writeln('- ${_t('wallet_payment_interest_rate', language)}: ${schedule.annualInterestRate.toStringAsFixed(2)}%');
      buffer.writeln('- ${_t('wallet_payment_total_interest', language)}: ${schedule.formatAmount(schedule.totalInterest)}');
    }
    buffer.writeln('- ${_t('wallet_payment_total_due', language)}: ${schedule.formatAmount(schedule.totalAmount)}');
    buffer.writeln('- ${_t('wallet_payment_final_date', language)}: ${schedule.installments.last.formattedDueDate}');

    buffer.writeln();
    buffer.writeln('### ${_t('wallet_obligation_title', language)}');
    buffer.writeln();
    buffer.writeln(_t('wallet_obligation_intro', language));
    buffer.writeln();

    if (schedule.numberOfInstallments == 1) {
      buffer.writeln('- ${_tParams('wallet_obligation_single', language, [
        schedule.formatAmount(schedule.totalAmount),
        schedule.installments.first.formattedDueDate,
      ])}');
    } else {
      buffer.writeln('- ${_tParams('wallet_obligation_installments', language, [
        schedule.numberOfInstallments.toString(),
      ])}');
      buffer.writeln('- ${_tParams('wallet_obligation_frequency', language, [
        schedule.paymentIntervalDays.toString(),
        schedule.installments.first.formattedDueDate,
      ])}');
      buffer.writeln('- ${_tParams('wallet_obligation_final', language, [
        schedule.finalDueDate.toString().substring(0, 10),
      ])}');
    }

    if (schedule.annualInterestRate > 0) {
      buffer.writeln();
      buffer.writeln(_t('wallet_obligation_interest_terms', language));
      buffer.writeln('- ${_tParams('wallet_obligation_interest_rate', language, [
        schedule.annualInterestRate.toStringAsFixed(2),
      ])}');
      buffer.writeln('- ${_t('wallet_obligation_interest_calc', language)}');
      buffer.writeln('- ${_tParams('wallet_obligation_interest_total', language, [
        schedule.formatAmount(schedule.totalInterest),
      ])}');
    }

    buffer.writeln();
    buffer.writeln('${_tParams('wallet_obligation_total', language, [
      schedule.formatAmount(schedule.totalAmount),
    ])}');

    return buffer.toString();
  }

  /// Build the full terms in the specified language.
  static String _buildTerms({
    String? governingJurisdiction,
    PaymentSchedule? paymentSchedule,
    required String language,
  }) {
    final buffer = StringBuffer();
    final jurisdiction = governingJurisdiction ?? 'the jurisdiction where the creditor resides';

    buffer.writeln('## ${_t('wallet_terms_title', language)}');
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_intro', language));
    buffer.writeln();

    // Section 1: Electronic Signatures
    buffer.writeln('### ${_t('wallet_terms_1_title', language)}');
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_1_1', language));
    buffer.writeln(_t('wallet_terms_1_1_us', language));
    buffer.writeln(_t('wallet_terms_1_1_eu', language));
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_1_2', language));
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_1_3', language));
    buffer.writeln();

    // Section 2: Acknowledgment of Debt
    buffer.writeln('### ${_t('wallet_terms_2_title', language)}');
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_2_1', language));
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_2_2', language));
    buffer.writeln();

    // Section 3: Record Retention
    buffer.writeln('### ${_t('wallet_terms_3_title', language)}');
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_3_1', language));
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_3_2', language));
    buffer.writeln();

    // Section 4: Identity Verification
    buffer.writeln('### ${_t('wallet_terms_4_title', language)}');
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_4_1', language));
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_4_2', language));
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_4_3', language));
    buffer.writeln();

    // Section 5: Amendments and Payments
    buffer.writeln('### ${_t('wallet_terms_5_title', language)}');
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_5_1', language));
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_5_2', language));
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_5_3', language));
    buffer.writeln();

    // Section 6: Witnesses
    buffer.writeln('### ${_t('wallet_terms_6_title', language)}');
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_6_1', language));
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_6_2', language));
    buffer.writeln();

    // Section 7: Dispute Resolution
    buffer.writeln('### ${_t('wallet_terms_7_title', language)}');
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_7_1', language));
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_7_2', language));
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_7_3', language));
    buffer.writeln();

    // Section 8: Governing Law
    buffer.writeln('### ${_t('wallet_terms_8_title', language)}');
    buffer.writeln();
    buffer.writeln(_tParams('wallet_terms_8_1', language, [jurisdiction]));
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_8_2', language));
    buffer.writeln();

    // Section 9: Severability
    buffer.writeln('### ${_t('wallet_terms_9_title', language)}');
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_9_1', language));
    buffer.writeln();

    // Section 10: Entire Agreement
    buffer.writeln('### ${_t('wallet_terms_10_title', language)}');
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_10_1', language));
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_10_2', language));

    // Interest sections if applicable
    if (paymentSchedule != null && paymentSchedule.annualInterestRate > 0) {
      buffer.writeln();
      buffer.write(_buildInterestTerms(paymentSchedule, language));
    }

    return buffer.toString();
  }

  /// Build interest-specific terms in the specified language.
  static String _buildInterestTerms(PaymentSchedule schedule, String language) {
    final buffer = StringBuffer();

    // Section 11: Interest Calculation
    buffer.writeln('### ${_t('wallet_terms_11_title', language)}');
    buffer.writeln();
    buffer.writeln(_tParams('wallet_terms_11_1', language, [
      schedule.annualInterestRate.toStringAsFixed(2),
    ]));
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_11_2', language));
    buffer.writeln();
    buffer.writeln(_tParams('wallet_terms_11_3', language, [
      (schedule.annualInterestRate / 365).toStringAsFixed(6),
    ]));
    buffer.writeln();
    buffer.writeln(_tParams('wallet_terms_11_4', language, [
      schedule.formatAmount(schedule.totalInterest),
    ]));
    buffer.writeln();
    buffer.writeln(_tParams('wallet_terms_11_5', language, [
      schedule.formatAmount(schedule.totalAmount),
    ]));
    buffer.writeln();

    // Section 12: Late Payment
    buffer.writeln('### ${_t('wallet_terms_12_title', language)}');
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_12_1', language));
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_12_2', language));
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_12_3', language));
    buffer.writeln();

    // Section 13: Early Repayment
    buffer.writeln('### ${_t('wallet_terms_13_title', language)}');
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_13_1', language));
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_13_2', language));
    buffer.writeln();
    buffer.writeln(_t('wallet_terms_13_3', language));

    return buffer.toString();
  }

  /// Get translation for a key in a specific language.
  ///
  /// Falls back to the key itself if translation not found.
  static String _t(String key, String language) {
    // For now, we use the translation maps directly
    // In a full implementation, this would load from the JSON files
    return _getTranslation(key, language);
  }

  /// Get translation with parameter substitution.
  static String _tParams(String key, String language, List<String> params) {
    var translation = _t(key, language);
    for (int i = 0; i < params.length; i++) {
      translation = translation.replaceAll('{$i}', params[i]);
    }
    return translation;
  }

  /// Get translation from embedded maps (compile-time safe).
  ///
  /// This duplicates some translations but ensures they're available
  /// even before the i18n service loads the JSON files.
  static String _getTranslation(String key, String language) {
    final translations = language.startsWith('pt')
        ? _portugueseTranslations
        : _englishTranslations;
    return translations[key] ?? key;
  }

  // Embedded translations for terms (ensures availability at compile time)
  static const _englishTranslations = {
    'wallet_terms_title': 'Terms and Conditions',
    'wallet_terms_intro': 'By signing this digital debt agreement, both parties agree to the following:',
    'wallet_terms_1_title': '1. Electronic Signatures and Records',
    'wallet_terms_1_1': '1.1. Both parties consent to conduct this transaction electronically and agree that electronic signatures are legally binding and equivalent to handwritten signatures under applicable law, including:',
    'wallet_terms_1_1_us': '- United States: Electronic Signatures in Global and National Commerce Act (E-SIGN Act) and Uniform Electronic Transactions Act (UETA)',
    'wallet_terms_1_1_eu': '- European Union: Regulation (EU) No 910/2014 (eIDAS) on electronic identification and trust services',
    'wallet_terms_1_2': '1.2. Each party confirms their intent to sign this agreement by adding their cryptographic signature (BIP-340 Schnorr signature via NOSTR protocol).',
    'wallet_terms_1_3': '1.3. Both parties agree that the signature chain mechanism, where each entry\'s signature covers all content above it, constitutes a valid and tamper-evident record of the agreement and all amendments.',
    'wallet_terms_2_title': '2. Acknowledgment of Debt',
    'wallet_terms_2_1': '2.1. The debtor acknowledges owing the specified amount to the creditor as stated in this agreement.',
    'wallet_terms_2_2': '2.2. The debtor agrees to repay the debt according to the terms specified, including any due date, payment schedule, or other conditions stated herein.',
    'wallet_terms_3_title': '3. Record Retention',
    'wallet_terms_3_1': '3.1. Both parties agree to retain a copy of this digital debt record for the duration of the debt plus the applicable statute of limitations period.',
    'wallet_terms_3_2': '3.2. Both parties acknowledge they can access, print, and store this electronic record.',
    'wallet_terms_4_title': '4. Identity Verification',
    'wallet_terms_4_1': '4.1. Each party represents that they are the rightful owner of the cryptographic keys used to sign this agreement.',
    'wallet_terms_4_2': '4.2. Each party\'s public key (npub) serves as their digital identity for this agreement.',
    'wallet_terms_4_3': '4.3. Where identity photos with proof codes are attached, both parties agree these constitute evidence of identity at the time of signing.',
    'wallet_terms_5_title': '5. Amendments and Payments',
    'wallet_terms_5_1': '5.1. Any amendments to this agreement, including payment records, must be signed by the relevant party and appended to this ledger.',
    'wallet_terms_5_2': '5.2. Payment confirmations require the creditor\'s signature to be considered acknowledged.',
    'wallet_terms_5_3': '5.3. The signature chain ensures that no prior entries can be modified without invalidating subsequent signatures.',
    'wallet_terms_6_title': '6. Witnesses',
    'wallet_terms_6_1': '6.1. Third-party witnesses may sign this agreement to provide additional attestation.',
    'wallet_terms_6_2': '6.2. Witness signatures are advisory and do not affect the primary obligations between creditor and debtor.',
    'wallet_terms_7_title': '7. Dispute Resolution',
    'wallet_terms_7_1': '7.1. In case of disputes, the parties agree to first attempt resolution through direct communication.',
    'wallet_terms_7_2': '7.2. The cryptographic record of this agreement, including all signed entries, shall be admissible as evidence in any legal proceedings.',
    'wallet_terms_7_3': '7.3. The parties acknowledge that cryptographic signatures provide non-repudiation and may be used to establish the authenticity of this agreement in court.',
    'wallet_terms_8_title': '8. Governing Law',
    'wallet_terms_8_1': '8.1. This agreement shall be governed by the laws of {0}.',
    'wallet_terms_8_2': '8.2. Both parties submit to the jurisdiction of courts in that location for any disputes arising from this agreement.',
    'wallet_terms_9_title': '9. Severability',
    'wallet_terms_9_1': '9.1. If any provision of these terms is found to be unenforceable, the remaining provisions shall continue in full force and effect.',
    'wallet_terms_10_title': '10. Entire Agreement',
    'wallet_terms_10_1': '10.1. This digital debt record, including the header, all signed entries, and these terms, constitutes the entire agreement between the parties.',
    'wallet_terms_10_2': '10.2. Any modifications must be added as signed entries to this ledger.',
    'wallet_terms_11_title': '11. Interest Calculation',
    'wallet_terms_11_1': '11.1. The annual interest rate for this debt is {0}%.',
    'wallet_terms_11_2': '11.2. Interest is calculated on the remaining principal balance using simple interest.',
    'wallet_terms_11_3': '11.3. The daily interest rate is {0}%.',
    'wallet_terms_11_4': '11.4. Total interest payable over the term of this debt: {0}.',
    'wallet_terms_11_5': '11.5. The total amount to be repaid (principal + interest): {0}.',
    'wallet_terms_12_title': '12. Late Payment',
    'wallet_terms_12_1': '12.1. Payments are due on or before the dates specified in the payment schedule above.',
    'wallet_terms_12_2': '12.2. Late payments may incur additional interest at the same rate on the overdue amount.',
    'wallet_terms_12_3': '12.3. The debtor agrees to notify the creditor if a payment will be late.',
    'wallet_terms_13_title': '13. Early Repayment',
    'wallet_terms_13_1': '13.1. The debtor may repay the debt in full at any time before the final due date.',
    'wallet_terms_13_2': '13.2. Early repayment will reduce the total interest payable proportionally.',
    'wallet_terms_13_3': '13.3. No early repayment penalty applies unless otherwise specified.',
    'wallet_terms_reference': 'This agreement is subject to the Standard Terms and Conditions for Digital Debt Agreements, which both parties accept by signing. These terms ensure compliance with US (E-SIGN Act, UETA) and EU (eIDAS) electronic signature laws.',
    'wallet_payment_schedule': 'Payment Schedule',
    'wallet_payment_number': '#',
    'wallet_payment_due_date': 'Due Date',
    'wallet_payment_principal': 'Principal',
    'wallet_payment_interest': 'Interest',
    'wallet_payment_total': 'Total',
    'wallet_payment_remaining': 'Remaining',
    'wallet_payment_summary': 'Summary',
    'wallet_payment_principal_label': 'Principal',
    'wallet_payment_interest_rate': 'Annual Interest Rate',
    'wallet_payment_total_interest': 'Total Interest',
    'wallet_payment_total_due': 'Total Amount Due',
    'wallet_payment_final_date': 'Final Payment Date',
    'wallet_obligation_title': 'Payment Obligation',
    'wallet_obligation_intro': 'The debtor agrees to repay this debt according to the following schedule:',
    'wallet_obligation_single': 'Single payment of {0} due on {1}',
    'wallet_obligation_installments': '{0} installments',
    'wallet_obligation_frequency': 'Payments due every {0} days starting {1}',
    'wallet_obligation_final': 'Final payment due on {0}',
    'wallet_obligation_interest_terms': 'Interest terms:',
    'wallet_obligation_interest_rate': 'Annual interest rate: {0}%',
    'wallet_obligation_interest_calc': 'Interest calculated on remaining principal balance',
    'wallet_obligation_interest_total': 'Total interest payable: {0}',
    'wallet_obligation_total': 'Total amount to be repaid: {0}',
  };

  static const _portugueseTranslations = {
    'wallet_terms_title': 'Termos e Condições',
    'wallet_terms_intro': 'Ao assinar este acordo digital de dívida, ambas as partes concordam com o seguinte:',
    'wallet_terms_1_title': '1. Assinaturas Eletrónicas e Registos',
    'wallet_terms_1_1': '1.1. Ambas as partes consentem em realizar esta transação eletronicamente e concordam que as assinaturas eletrónicas são juridicamente vinculativas e equivalentes a assinaturas manuscritas nos termos da lei aplicável, incluindo:',
    'wallet_terms_1_1_us': '- Estados Unidos: Lei de Assinaturas Eletrónicas no Comércio Global e Nacional (E-SIGN Act) e Lei Uniforme de Transações Eletrónicas (UETA)',
    'wallet_terms_1_1_eu': '- União Europeia: Regulamento (UE) N.º 910/2014 (eIDAS) sobre identificação eletrónica e serviços de confiança',
    'wallet_terms_1_2': '1.2. Cada parte confirma a sua intenção de assinar este acordo através da adição da sua assinatura criptográfica (assinatura BIP-340 Schnorr via protocolo NOSTR).',
    'wallet_terms_1_3': '1.3. Ambas as partes concordam que o mecanismo de cadeia de assinaturas, onde a assinatura de cada entrada cobre todo o conteúdo acima dela, constitui um registo válido e à prova de adulteração do acordo e de todas as alterações.',
    'wallet_terms_2_title': '2. Reconhecimento da Dívida',
    'wallet_terms_2_1': '2.1. O devedor reconhece dever o montante especificado ao credor conforme estabelecido neste acordo.',
    'wallet_terms_2_2': '2.2. O devedor concorda em reembolsar a dívida de acordo com os termos especificados, incluindo qualquer data de vencimento, calendário de pagamentos ou outras condições aqui estabelecidas.',
    'wallet_terms_3_title': '3. Retenção de Registos',
    'wallet_terms_3_1': '3.1. Ambas as partes concordam em reter uma cópia deste registo digital de dívida durante a vigência da dívida mais o período de prescrição aplicável.',
    'wallet_terms_3_2': '3.2. Ambas as partes reconhecem que podem aceder, imprimir e armazenar este registo eletrónico.',
    'wallet_terms_4_title': '4. Verificação de Identidade',
    'wallet_terms_4_1': '4.1. Cada parte declara que é o legítimo proprietário das chaves criptográficas utilizadas para assinar este acordo.',
    'wallet_terms_4_2': '4.2. A chave pública de cada parte (npub) serve como a sua identidade digital para este acordo.',
    'wallet_terms_4_3': '4.3. Quando fotografias de identidade com códigos de prova estão anexadas, ambas as partes concordam que estas constituem prova de identidade no momento da assinatura.',
    'wallet_terms_5_title': '5. Alterações e Pagamentos',
    'wallet_terms_5_1': '5.1. Quaisquer alterações a este acordo, incluindo registos de pagamentos, devem ser assinadas pela parte relevante e anexadas a este livro-razão.',
    'wallet_terms_5_2': '5.2. As confirmações de pagamento requerem a assinatura do credor para serem consideradas reconhecidas.',
    'wallet_terms_5_3': '5.3. A cadeia de assinaturas garante que nenhuma entrada anterior pode ser modificada sem invalidar as assinaturas subsequentes.',
    'wallet_terms_6_title': '6. Testemunhas',
    'wallet_terms_6_1': '6.1. Testemunhas terceiras podem assinar este acordo para fornecer atestação adicional.',
    'wallet_terms_6_2': '6.2. As assinaturas de testemunhas são consultivas e não afetam as obrigações primárias entre credor e devedor.',
    'wallet_terms_7_title': '7. Resolução de Litígios',
    'wallet_terms_7_1': '7.1. Em caso de litígios, as partes concordam em primeiro tentar a resolução através de comunicação direta.',
    'wallet_terms_7_2': '7.2. O registo criptográfico deste acordo, incluindo todas as entradas assinadas, será admissível como prova em quaisquer processos judiciais.',
    'wallet_terms_7_3': '7.3. As partes reconhecem que as assinaturas criptográficas proporcionam não-repúdio e podem ser utilizadas para estabelecer a autenticidade deste acordo em tribunal.',
    'wallet_terms_8_title': '8. Lei Aplicável',
    'wallet_terms_8_1': '8.1. Este acordo será regido pelas leis de {0}.',
    'wallet_terms_8_2': '8.2. Ambas as partes submetem-se à jurisdição dos tribunais desse local para quaisquer litígios decorrentes deste acordo.',
    'wallet_terms_9_title': '9. Divisibilidade',
    'wallet_terms_9_1': '9.1. Se qualquer disposição destes termos for considerada inexequível, as restantes disposições continuarão em pleno vigor e efeito.',
    'wallet_terms_10_title': '10. Acordo Integral',
    'wallet_terms_10_1': '10.1. Este registo digital de dívida, incluindo o cabeçalho, todas as entradas assinadas e estes termos, constitui o acordo integral entre as partes.',
    'wallet_terms_10_2': '10.2. Quaisquer modificações devem ser adicionadas como entradas assinadas a este livro-razão.',
    'wallet_terms_11_title': '11. Cálculo de Juros',
    'wallet_terms_11_1': '11.1. A taxa de juro anual para esta dívida é de {0}%.',
    'wallet_terms_11_2': '11.2. Os juros são calculados sobre o saldo de capital remanescente usando juros simples.',
    'wallet_terms_11_3': '11.3. A taxa de juro diária é de {0}%.',
    'wallet_terms_11_4': '11.4. Total de juros a pagar durante o prazo desta dívida: {0}.',
    'wallet_terms_11_5': '11.5. O montante total a reembolsar (capital + juros): {0}.',
    'wallet_terms_12_title': '12. Pagamento em Atraso',
    'wallet_terms_12_1': '12.1. Os pagamentos são devidos até às datas especificadas no calendário de pagamentos acima.',
    'wallet_terms_12_2': '12.2. Pagamentos em atraso podem incorrer em juros adicionais à mesma taxa sobre o montante em dívida.',
    'wallet_terms_12_3': '12.3. O devedor concorda em notificar o credor se um pagamento estiver atrasado.',
    'wallet_terms_13_title': '13. Reembolso Antecipado',
    'wallet_terms_13_1': '13.1. O devedor pode reembolsar a dívida na totalidade a qualquer momento antes da data de vencimento final.',
    'wallet_terms_13_2': '13.2. O reembolso antecipado reduzirá proporcionalmente o total de juros a pagar.',
    'wallet_terms_13_3': '13.3. Não se aplica penalização por reembolso antecipado, salvo especificação em contrário.',
    'wallet_terms_reference': 'Este acordo está sujeito aos Termos e Condições Padrão para Acordos Digitais de Dívida, que ambas as partes aceitam ao assinar. Estes termos garantem conformidade com as leis de assinatura eletrónica dos EUA (E-SIGN Act, UETA) e da UE (eIDAS).',
    'wallet_payment_schedule': 'Calendário de Pagamentos',
    'wallet_payment_number': '#',
    'wallet_payment_due_date': 'Data de Vencimento',
    'wallet_payment_principal': 'Capital',
    'wallet_payment_interest': 'Juros',
    'wallet_payment_total': 'Total',
    'wallet_payment_remaining': 'Restante',
    'wallet_payment_summary': 'Resumo',
    'wallet_payment_principal_label': 'Capital',
    'wallet_payment_interest_rate': 'Taxa de Juro Anual',
    'wallet_payment_total_interest': 'Juros Totais',
    'wallet_payment_total_due': 'Montante Total a Pagar',
    'wallet_payment_final_date': 'Data do Último Pagamento',
    'wallet_obligation_title': 'Obrigação de Pagamento',
    'wallet_obligation_intro': 'O devedor concorda em reembolsar esta dívida de acordo com o seguinte calendário:',
    'wallet_obligation_single': 'Pagamento único de {0} com vencimento em {1}',
    'wallet_obligation_installments': '{0} prestações',
    'wallet_obligation_frequency': 'Pagamentos devidos a cada {0} dias a partir de {1}',
    'wallet_obligation_final': 'Último pagamento com vencimento em {0}',
    'wallet_obligation_interest_terms': 'Termos de juros:',
    'wallet_obligation_interest_rate': 'Taxa de juro anual: {0}%',
    'wallet_obligation_interest_calc': 'Juros calculados sobre o saldo de capital remanescente',
    'wallet_obligation_interest_total': 'Total de juros a pagar: {0}',
    'wallet_obligation_total': 'Montante total a reembolsar: {0}',
  };

  /// Short version of terms for display in UI.
  static String getShortTermsSummary({String? language}) {
    final lang = language ?? I18nService().currentLanguage;
    if (lang.startsWith('pt')) {
      return '''
Ao assinar, ambas as partes concordam que:
• As assinaturas eletrónicas são juridicamente vinculativas (EUA E-SIGN/UETA, UE eIDAS)
• O devedor reconhece a dívida e concorda em reembolsar
• A cadeia de assinaturas criptográficas é à prova de adulteração
• Este registo é admissível como prova em processos judiciais
• Os litígios são regidos pela jurisdição do credor
''';
    }
    return '''
By signing, both parties agree that:
• Electronic signatures are legally binding (US E-SIGN/UETA, EU eIDAS)
• The debtor acknowledges the debt and agrees to repay
• The cryptographic signature chain is tamper-evident
• This record is admissible as evidence in legal proceedings
• Disputes are governed by the creditor's jurisdiction
''';
  }
}
