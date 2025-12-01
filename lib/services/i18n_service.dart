import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'log_service.dart';
import 'config_service.dart';

class I18nService {
  static final I18nService _instance = I18nService._internal();
  factory I18nService() => _instance;
  I18nService._internal();

  Map<String, String> _translations = {};
  String _currentLanguage = 'en_US';
  final List<String> _supportedLanguages = ['en_US', 'pt_PT'];

  // Language display names
  final Map<String, String> _languageNames = {
    'en_US': 'English (US)',
    'pt_PT': 'Português (Portugal)',
  };

  // Notifier for UI updates when language changes
  final ValueNotifier<String> languageNotifier = ValueNotifier<String>('en_US');

  /// Initialize the i18n service with a default language
  Future<void> init({String? language}) async {
    LogService().log('I18nService initializing...');

    // Try to load saved language from config, or use provided, or default to en_US
    String languageToLoad = language ??
                           ConfigService().getNestedValue('settings.language', 'en_US') as String;

    // Validate language is supported
    if (!_supportedLanguages.contains(languageToLoad)) {
      LogService().log('WARNING: Unsupported language $languageToLoad, falling back to en_US');
      languageToLoad = 'en_US';
    }

    _currentLanguage = languageToLoad;
    await _loadLanguage(_currentLanguage);
    languageNotifier.value = _currentLanguage;

    LogService().log('I18nService initialized with language: $_currentLanguage');
  }

  /// Load a language file
  Future<void> _loadLanguage(String language) async {
    try {
      LogService().log('Loading language file: $language');

      // Load the JSON file from assets
      final String jsonString = await rootBundle.loadString('languages/$language.json');
      final Map<String, dynamic> jsonMap = json.decode(jsonString);

      // Convert to Map<String, String>
      _translations = jsonMap.map((key, value) => MapEntry(key, value.toString()));

      LogService().log('Language file loaded successfully: $language (${_translations.length} translations)');
    } catch (e, stackTrace) {
      LogService().log('ERROR loading language file $language: $e');
      LogService().log('Stack trace: $stackTrace');

      // If loading fails, ensure we have empty translations rather than crashing
      _translations = {};
    }
  }

  /// Change the current language
  Future<void> setLanguage(String language) async {
    if (!_supportedLanguages.contains(language)) {
      LogService().log('ERROR: Cannot set unsupported language: $language');
      return;
    }

    if (_currentLanguage == language) {
      LogService().log('Language $language is already set');
      return;
    }

    LogService().log('Changing language from $_currentLanguage to $language');
    _currentLanguage = language;
    await _loadLanguage(language);

    // Save to config for persistence
    ConfigService().setNestedValue('settings.language', language);

    languageNotifier.value = language;

    LogService().log('Language changed successfully to: $language');
  }

  /// Get a translated string by key
  /// Supports parameter substitution with {0}, {1}, etc.
  String translate(String key, {List<String>? params}) {
    String translation = _translations[key] ?? key;

    // If parameters are provided, substitute them
    if (params != null && params.isNotEmpty) {
      for (int i = 0; i < params.length; i++) {
        translation = translation.replaceAll('{$i}', params[i]);
      }
    }

    return translation;
  }

  /// Shorthand for translate
  String t(String key, {List<String>? params}) {
    return translate(key, params: params);
  }

  /// Get the current language code
  String get currentLanguage => _currentLanguage;

  /// Get list of supported languages
  List<String> get supportedLanguages => List.unmodifiable(_supportedLanguages);

  /// Get language display name
  String getLanguageName(String languageCode) {
    return _languageNames[languageCode] ?? languageCode;
  }

  /// Get all language names as a map
  Map<String, String> get languageNames => Map.unmodifiable(_languageNames);
}

/// Extension to make translation easier in widgets
extension I18nExtension on String {
  String get tr => I18nService().translate(this);
  String trParams(List<String> params) => I18nService().translate(this, params: params);
}
