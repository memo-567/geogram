import 'dart:io' if (dart.library.html) '../../platform/io_stub.dart' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../models/tracker_models.dart';
import '../services/path_recording_service.dart';
import '../../widgets/transcribe_button_widget.dart';
import '../../services/i18n_service.dart';
import '../../services/location_service.dart';
import '../../services/user_location_service.dart';
import '../../util/geolocation_utils.dart';

/// Dialog for starting a new path recording
class StartPathDialog extends StatefulWidget {
  final PathRecordingService recordingService;
  final I18nService i18n;

  const StartPathDialog({
    super.key,
    required this.recordingService,
    required this.i18n,
  });

  static Future<TrackerPath?> show(
    BuildContext context, {
    required PathRecordingService recordingService,
    required I18nService i18n,
  }) {
    return showDialog<TrackerPath>(
      context: context,
      builder: (context) => StartPathDialog(
        recordingService: recordingService,
        i18n: i18n,
      ),
    );
  }

  @override
  State<StartPathDialog> createState() => _StartPathDialogState();
}

class _StartPathDialogState extends State<StartPathDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final UserLocationService _userLocationService = UserLocationService();
  final LocationService _locationService = LocationService();

  TrackerPathType _selectedType = TrackerPathType.travel;
  int _intervalSeconds = 0;
  bool _starting = false;
  bool _customTitle = false;
  bool _settingAutoTitle = false;
  String? _autoCityLabel;
  double? _lastCityLat;
  double? _lastCityLon;

  // Available GPS intervals
  static const _intervals = [
    (0, 'auto'),
    (15, '15s'),
    (30, '30s'),
    (60, '1m'),
    (120, '2m'),
    (300, '5m'),
  ];

  @override
  void initState() {
    super.initState();
    _updateAutoTitle();
    _userLocationService.addListener(_onLocationChanged);
    _refreshAutoCity();
  }

  @override
  void dispose() {
    _userLocationService.removeListener(_onLocationChanged);
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _onLocationChanged() {
    if (!mounted) return;
    _refreshAutoCity();
  }

  Future<void> _refreshAutoCity() async {
    final location = _userLocationService.currentLocation;
    if (location == null || !location.isValid) {
      return;
    }

    if (_lastCityLat != null && _lastCityLon != null) {
      final distanceKm = _locationService.calculateDistance(
        _lastCityLat!,
        _lastCityLon!,
        location.latitude,
        location.longitude,
      );
      if (distanceKm < 2) {
        return;
      }
    }

    _lastCityLat = location.latitude;
    _lastCityLon = location.longitude;

    final fallbackName = location.locationName?.trim();
    if (fallbackName != null && fallbackName.isNotEmpty) {
      _autoCityLabel = fallbackName;
      _updateAutoTitle();
      return;
    }

    final nearestCity = await _locationService.findNearestCity(
      location.latitude,
      location.longitude,
    );
    if (!mounted) return;

    if (nearestCity != null) {
      _autoCityLabel = '${nearestCity.city}, ${nearestCity.country}';
      _updateAutoTitle();
    }
  }

  void _updateAutoTitle() {
    if (_customTitle) {
      return;
    }

    final now = DateTime.now();
    final hour = now.hour;

    // Determine time of day
    String timeOfDay;
    if (hour < 12) {
      timeOfDay = widget.i18n.t('tracker_morning');
    } else if (hour < 17) {
      timeOfDay = widget.i18n.t('tracker_afternoon');
    } else if (hour < 21) {
      timeOfDay = widget.i18n.t('tracker_evening');
    } else {
      timeOfDay = widget.i18n.t('tracker_night');
    }

    // Get localized path type name
    final typeName = widget.i18n.t(_selectedType.translationKey);

    // Format date
    final dateFormat = DateFormat.MMMd();
    final dateStr = dateFormat.format(now);

    final buffer = StringBuffer('$timeOfDay $typeName');
    final cityLabel = _autoCityLabel?.trim();
    if (cityLabel != null && cityLabel.isNotEmpty) {
      buffer.write(' - $cityLabel');
    }
    buffer.write(' - $dateStr');

    _settingAutoTitle = true;
    _titleController
      ..text = buffer.toString()
      ..selection = TextSelection.collapsed(
        offset: _titleController.text.length,
      );
    _settingAutoTitle = false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.i18n.t('tracker_start_path')),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Path type dropdown
              DropdownButtonFormField<TrackerPathType>(
                value: _selectedType,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: widget.i18n.t('tracker_path_type'),
                  border: const OutlineInputBorder(),
                ),
                items: TrackerPathType.values
                    .map((type) => DropdownMenuItem(
                          value: type,
                          child: Row(
                            children: [
                              Icon(type.icon, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.i18n.t(type.translationKey),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedType = value;
                    });
                    _updateAutoTitle();
                  }
                },
              ),
              const SizedBox(height: 16),

              // Title field
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: widget.i18n.t('tracker_path_title'),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) {
                  if (_settingAutoTitle) return;
                  if (!_customTitle) {
                    setState(() => _customTitle = true);
                  }
                },
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return widget.i18n.t('tracker_required_field');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Description field (optional)
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: widget.i18n.t('tracker_path_description'),
                  border: const OutlineInputBorder(),
                  suffixIcon: TranscribeButtonWidget(
                    i18n: widget.i18n,
                    onTranscribed: (text) {
                      final current = _descriptionController.text;
                      final needsSpace =
                          current.isNotEmpty && !current.endsWith(' ');
                      final appended = '$current${needsSpace ? ' ' : ''}$text';
                      _descriptionController
                        ..text = appended
                        ..selection = TextSelection.collapsed(
                          offset: appended.length,
                        );
                    },
                    enabled: !_starting,
                  ),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              // GPS interval selector
              DropdownButtonFormField<int>(
                value: _intervalSeconds,
                decoration: InputDecoration(
                  labelText: widget.i18n.t('tracker_gps_interval'),
                  border: const OutlineInputBorder(),
                ),
                items: _intervals
                    .map((interval) => DropdownMenuItem(
                          value: interval.$1,
                          child: Text(widget.i18n.t('tracker_interval_${interval.$2}')),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _intervalSeconds = value);
                  }
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _starting ? null : () => Navigator.of(context).pop(null),
          child: Text(widget.i18n.t('cancel')),
        ),
        FilledButton.icon(
          onPressed: _starting ? null : _start,
          icon: _starting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
          label: Text(widget.i18n.t('tracker_start_recording')),
        ),
      ],
    );
  }

  Future<void> _start() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _starting = true);

    try {
      final path = await widget.recordingService.startRecording(
        pathType: _selectedType,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        intervalSeconds: _intervalSeconds,
        notificationTitle: widget.i18n.t('location_recording_title'),
        notificationText: widget.i18n.t('location_recording_text'),
      );

      if (mounted) {
        if (path != null) {
          Navigator.of(context).pop(path);
        } else {
          final message = await _resolveStartErrorMessage();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
            ),
          );
          setState(() => _starting = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.i18n.t('tracker_error_starting_path'))),
        );
        setState(() => _starting = false);
      }
    }
  }

  Future<String> _resolveStartErrorMessage() async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return widget.i18n.t('tracker_error_starting_path');
    }

    final permission = await GeolocationUtils.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return widget.i18n.t('tracker_gps_permission_required');
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return widget.i18n.t('tracker_gps_disabled');
    }

    return widget.i18n.t('tracker_error_starting_path');
  }
}
