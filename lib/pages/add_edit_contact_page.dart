/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:io' if (dart.library.html) '../platform/io_stub.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:latlong2/latlong.dart';
import '../dialogs/place_picker_dialog.dart';
import '../models/contact.dart';
import '../models/place.dart';
import '../platform/file_image_helper.dart' as file_helper;
import '../services/contact_service.dart';
import '../services/profile_service.dart';
import '../services/i18n_service.dart';
import '../services/location_service.dart';
import '../util/nostr_key_generator.dart';
import 'location_picker_page.dart';

/// Full-page form for adding or editing a contact
class AddEditContactPage extends StatefulWidget {
  final String collectionPath;
  final Contact? contact; // null for new contact, non-null for edit
  final String? groupPath; // folder path for new contacts

  const AddEditContactPage({
    Key? key,
    required this.collectionPath,
    this.contact,
    this.groupPath,
  }) : super(key: key);

  @override
  State<AddEditContactPage> createState() => _AddEditContactPageState();
}

class _AddEditContactPageState extends State<AddEditContactPage> {
  final ContactService _contactService = ContactService();
  final ProfileService _profileService = ProfileService();
  final I18nService _i18n = I18nService();
  final _formKey = GlobalKey<FormState>();

  // Controllers for single-value fields
  late TextEditingController _displayNameController;
  late TextEditingController _npubController;
  late TextEditingController _notesController;
  late TextEditingController _tagsController;

  // Lists for multi-value fields
  List<TextEditingController> _emailControllers = [];
  List<TextEditingController> _phoneControllers = [];
  List<TextEditingController> _addressControllers = [];
  List<TextEditingController> _websiteControllers = [];
  List<Map<String, dynamic>> _locationControllers = []; // name, lat, long controllers + type + place
  List<Map<String, dynamic>> _socialHandleControllers = [];

  // Profile picture
  String? _selectedProfilePicturePath;
  String? _existingProfilePicture;

  // Tags
  List<String> _tags = [];

  bool _isLoading = false;
  bool _isSaving = false;

  // Top social networks by popularity
  static const List<Map<String, String>> _socialNetworks = [
    {'id': 'facebook', 'name': 'Facebook', 'prefix': 'facebook.com/'},
    {'id': 'youtube', 'name': 'YouTube', 'prefix': 'youtube.com/@'},
    {'id': 'whatsapp', 'name': 'WhatsApp', 'prefix': '+'},
    {'id': 'instagram', 'name': 'Instagram', 'prefix': '@'},
    {'id': 'tiktok', 'name': 'TikTok', 'prefix': '@'},
    {'id': 'wechat', 'name': 'WeChat', 'prefix': ''},
    {'id': 'facebook_messenger', 'name': 'Messenger', 'prefix': ''},
    {'id': 'telegram', 'name': 'Telegram', 'prefix': '@'},
    {'id': 'snapchat', 'name': 'Snapchat', 'prefix': '@'},
    {'id': 'douyin', 'name': 'Douyin', 'prefix': '@'},
    {'id': 'kuaishou', 'name': 'Kuaishou', 'prefix': '@'},
    {'id': 'x', 'name': 'X (Twitter)', 'prefix': '@'},
    {'id': 'linkedin', 'name': 'LinkedIn', 'prefix': 'linkedin.com/in/'},
    {'id': 'pinterest', 'name': 'Pinterest', 'prefix': '@'},
    {'id': 'reddit', 'name': 'Reddit', 'prefix': 'u/'},
    {'id': 'discord', 'name': 'Discord', 'prefix': ''},
    {'id': 'qq', 'name': 'QQ', 'prefix': ''},
    {'id': 'quora', 'name': 'Quora', 'prefix': ''},
    {'id': 'skype', 'name': 'Skype', 'prefix': ''},
    {'id': 'viber', 'name': 'Viber', 'prefix': '+'},
    {'id': 'line', 'name': 'Line', 'prefix': ''},
    {'id': 'twitch', 'name': 'Twitch', 'prefix': 'twitch.tv/'},
    {'id': 'tumblr', 'name': 'Tumblr', 'prefix': '@'},
    {'id': 'vk', 'name': 'VK', 'prefix': 'vk.com/'},
    {'id': 'weibo', 'name': 'Weibo', 'prefix': '@'},
    {'id': 'threads', 'name': 'Threads', 'prefix': '@'},
    {'id': 'bluesky', 'name': 'Bluesky', 'prefix': '@'},
    {'id': 'mastodon', 'name': 'Mastodon', 'prefix': '@'},
    {'id': 'signal', 'name': 'Signal', 'prefix': '+'},
    {'id': 'slack', 'name': 'Slack', 'prefix': ''},
    {'id': 'teams', 'name': 'Teams', 'prefix': ''},
    {'id': 'zoom', 'name': 'Zoom', 'prefix': ''},
    {'id': 'clubhouse', 'name': 'Clubhouse', 'prefix': '@'},
    {'id': 'kakaotalk', 'name': 'KakaoTalk', 'prefix': ''},
    {'id': 'naver', 'name': 'Naver', 'prefix': ''},
    {'id': 'zalo', 'name': 'Zalo', 'prefix': '+'},
    {'id': 'imo', 'name': 'imo', 'prefix': '+'},
    {'id': 'likee', 'name': 'Likee', 'prefix': '@'},
    {'id': 'picsart', 'name': 'Picsart', 'prefix': '@'},
    {'id': 'helo', 'name': 'Helo', 'prefix': '@'},
    {'id': 'sharechat', 'name': 'ShareChat', 'prefix': '@'},
    {'id': 'moj', 'name': 'Moj', 'prefix': '@'},
    {'id': 'josh', 'name': 'Josh', 'prefix': '@'},
    {'id': 'triller', 'name': 'Triller', 'prefix': '@'},
    {'id': 'lemon8', 'name': 'Lemon8', 'prefix': '@'},
    {'id': 'bereal', 'name': 'BeReal', 'prefix': '@'},
    {'id': 'truth_social', 'name': 'Truth Social', 'prefix': '@'},
    {'id': 'parler', 'name': 'Parler', 'prefix': '@'},
    {'id': 'gettr', 'name': 'Gettr', 'prefix': '@'},
    {'id': 'gab', 'name': 'Gab', 'prefix': '@'},
    {'id': 'other', 'name': 'Other', 'prefix': ''},
  ];

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _initializeService();
  }

  Future<void> _initializeService() async {
    await _contactService.initializeCollection(widget.collectionPath);
  }

  void _initializeControllers() {
    final contact = widget.contact;

    _displayNameController = TextEditingController(text: contact?.displayName ?? '');
    _npubController = TextEditingController(text: contact?.npub ?? '');
    _notesController = TextEditingController(text: contact?.notes ?? '');
    _tagsController = TextEditingController();

    // Initialize multi-value fields
    if (contact != null) {
      _emailControllers = contact.emails.map((e) => TextEditingController(text: e)).toList();
      _phoneControllers = contact.phones.map((p) => TextEditingController(text: p)).toList();
      _addressControllers = contact.addresses.map((a) => TextEditingController(text: a)).toList();
      _websiteControllers = contact.websites.map((w) => TextEditingController(text: w)).toList();
      _locationControllers = contact.locations.map((loc) => <String, dynamic>{
        'name': TextEditingController(text: loc.name),
        'lat': TextEditingController(text: loc.latitude?.toString() ?? ''),
        'long': TextEditingController(text: loc.longitude?.toString() ?? ''),
        'type': loc.type.name, // 'coordinates', 'place', 'online'
        'place': loc.placePath,
      }).toList();
      _tags = List.from(contact.tags);
      _existingProfilePicture = contact.profilePicture;

      // Initialize social handles from contact
      if (contact.socialHandles.isNotEmpty) {
        _socialHandleControllers = contact.socialHandles.entries.map((entry) {
          return {
            'network': entry.key,
            'controller': TextEditingController(text: entry.value),
          };
        }).toList();
      }
    }

    // Add at least one empty field for each multi-value type
    if (_emailControllers.isEmpty) _emailControllers.add(TextEditingController());
    if (_phoneControllers.isEmpty) _phoneControllers.add(TextEditingController());
    if (_addressControllers.isEmpty) _addressControllers.add(TextEditingController());
    if (_websiteControllers.isEmpty) _websiteControllers.add(TextEditingController());
    if (_locationControllers.isEmpty) {
      _locationControllers.add(<String, dynamic>{
        'name': TextEditingController(),
        'lat': TextEditingController(),
        'long': TextEditingController(),
        'type': 'coordinates',
        'place': null,
      });
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _npubController.dispose();
    _notesController.dispose();
    _tagsController.dispose();

    for (var controller in _emailControllers) controller.dispose();
    for (var controller in _phoneControllers) controller.dispose();
    for (var controller in _addressControllers) controller.dispose();
    for (var controller in _websiteControllers) controller.dispose();
    for (var controllers in _locationControllers) {
      (controllers['name'] as TextEditingController?)?.dispose();
      (controllers['lat'] as TextEditingController?)?.dispose();
      (controllers['long'] as TextEditingController?)?.dispose();
    }
    for (var handle in _socialHandleControllers) {
      (handle['controller'] as TextEditingController).dispose();
    }

    super.dispose();
  }

  void _addField(List<dynamic> controllers) {
    setState(() {
      if (controllers == _locationControllers) {
        controllers.add(<String, dynamic>{
          'name': TextEditingController(),
          'lat': TextEditingController(),
          'long': TextEditingController(),
          'type': 'coordinates',
          'place': null,
        });
      } else {
        controllers.add(TextEditingController());
      }
    });
  }

  void _removeField(List<dynamic> controllers, int index) {
    setState(() {
      if (controllers == _locationControllers) {
        final loc = controllers[index] as Map<String, dynamic>;
        (loc['name'] as TextEditingController?)?.dispose();
        (loc['lat'] as TextEditingController?)?.dispose();
        (loc['long'] as TextEditingController?)?.dispose();
      } else {
        (controllers[index] as TextEditingController).dispose();
      }
      controllers.removeAt(index);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Collect values
      final displayName = _displayNameController.text.trim();
      final npub = _npubController.text.trim();
      final notes = _notesController.text.trim();

      final emails = _emailControllers
          .map((c) => c.text.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final phones = _phoneControllers
          .map((c) => c.text.trim())
          .where((p) => p.isNotEmpty)
          .toList();

      final addresses = _addressControllers
          .map((c) => c.text.trim())
          .where((a) => a.isNotEmpty)
          .toList();

      final websites = _websiteControllers
          .map((c) => c.text.trim())
          .where((w) => w.isNotEmpty)
          .toList();

      final locations = _locationControllers
          .where((loc) => (loc['name'] as TextEditingController).text.trim().isNotEmpty)
          .map((loc) {
            final name = (loc['name'] as TextEditingController).text.trim();
            final typeStr = loc['type'] as String? ?? 'coordinates';
            final placePath = loc['place'] as String?;
            final latText = (loc['lat'] as TextEditingController).text.trim();
            final longText = (loc['long'] as TextEditingController).text.trim();

            double? lat;
            double? long;

            if (latText.isNotEmpty) {
              lat = double.tryParse(latText);
            }
            if (longText.isNotEmpty) {
              long = double.tryParse(longText);
            }

            return ContactLocation(
              name: name,
              type: ContactLocation.parseType(typeStr),
              latitude: lat,
              longitude: long,
              placePath: placePath,
            );
          })
          .toList();

      // Collect social handles
      final socialHandles = <String, String>{};
      for (final handle in _socialHandleControllers) {
        final network = handle['network'] as String;
        final controller = handle['controller'] as TextEditingController;
        final value = controller.text.trim();
        if (value.isNotEmpty) {
          socialHandles[network] = value;
        }
      }

      // Create timestamp for new contacts, preserve for edits
      final now = DateTime.now();
      final timestamp = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}_${now.second.toString().padLeft(2, '0')}';

      // Preserve original timestamps when editing
      final created = widget.contact?.created ?? timestamp;
      final firstSeen = widget.contact?.firstSeen ?? timestamp;

      // Handle temporary identity generation (always generate for new contacts)
      String? finalNpub = npub.isNotEmpty ? npub : widget.contact?.npub;
      String? finalTemporaryNsec = widget.contact?.temporaryNsec;
      bool finalIsTemporaryIdentity = widget.contact?.isTemporaryIdentity ?? false;
      String callsign = widget.contact?.callsign ?? '';

      // Generate new identity if no npub provided and not editing existing contact
      if (finalNpub == null || finalNpub.isEmpty) {
        final tempKeys = NostrKeyGenerator.generateKeyPair();
        finalNpub = tempKeys.npub;
        finalTemporaryNsec = tempKeys.nsec;
        finalIsTemporaryIdentity = true;
        callsign = tempKeys.callsign;
      } else if (callsign.isEmpty) {
        // Derive callsign from npub if editing with new npub
        callsign = NostrKeyGenerator.deriveCallsign(finalNpub);
      }

      // Handle profile picture (use derived callsign)
      String? profilePicture = _existingProfilePicture;
      if (_selectedProfilePicturePath != null) {
        final sourceFile = File(_selectedProfilePicturePath!);
        profilePicture = await _contactService.saveProfilePicture(callsign, sourceFile);
      }

      // Use group path from widget (passed from current folder) or existing contact's path
      final groupPath = widget.groupPath ?? widget.contact?.groupPath;

      // Create contact object
      final contact = Contact(
        displayName: displayName,
        callsign: callsign,
        npub: finalNpub,
        created: created,
        firstSeen: firstSeen,
        emails: emails,
        phones: phones,
        addresses: addresses,
        websites: websites,
        locations: locations,
        socialHandles: socialHandles,
        profilePicture: profilePicture,
        tags: _tags,
        isTemporaryIdentity: finalIsTemporaryIdentity,
        temporaryNsec: finalTemporaryNsec,
        historyEntries: widget.contact?.historyEntries ?? [],
        notes: notes,
        groupPath: groupPath,
        filePath: widget.contact?.filePath,
      );

      // Save contact
      final error = await _contactService.saveContact(
        contact,
        groupPath: groupPath,
      );

      if (error != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error), backgroundColor: Colors.red),
          );
        }
      } else {
        if (mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.contact != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? _i18n.t('edit') : _i18n.t('new_contact')),
        actions: [
          if (!_isSaving)
            TextButton(
              onPressed: _save,
              child: Text(
                _i18n.t('save'),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Required Fields Section
                  Text(
                    _i18n.t('required_fields'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _displayNameController,
                    decoration: InputDecoration(
                      labelText: '${_i18n.t('display_name')} *',
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return _i18n.t('field_required');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  TextFormField(
                    controller: _npubController,
                    decoration: InputDecoration(
                      labelText: _i18n.t('npub_optional'),
                      border: const OutlineInputBorder(),
                      hintText: 'npub1... (${_i18n.t('optional')})',
                      helperText: _i18n.t('npub_optional_hint'),
                    ),
                    validator: (value) {
                      // Only validate format if a value is provided
                      if (value != null && value.trim().isNotEmpty) {
                        if (!value.startsWith('npub1')) {
                          return _i18n.t('invalid_npub');
                        }
                      }
                      return null; // Empty is valid (optional)
                    },
                  ),
                  const SizedBox(height: 24),

                  // Profile Picture Section
                  _buildProfilePictureSection(),
                  const SizedBox(height: 24),

                  // Tags Section
                  _buildTagsSection(),
                  const SizedBox(height: 24),

                  // Optional Fields Section
                  Text(
                    _i18n.t('optional_fields'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),

                  // Email addresses
                  _buildMultiValueSection(
                    _i18n.t('email_addresses'),
                    _emailControllers,
                    Icons.email,
                    TextInputType.emailAddress,
                    'user@example.com',
                  ),

                  // Phone numbers
                  _buildMultiValueSection(
                    _i18n.t('phone_numbers'),
                    _phoneControllers,
                    Icons.phone,
                    TextInputType.phone,
                    '+1-555-0123',
                  ),

                  // Addresses
                  _buildMultiValueSection(
                    _i18n.t('addresses'),
                    _addressControllers,
                    Icons.home,
                    TextInputType.streetAddress,
                    '123 Main St, City, Country',
                  ),

                  // Websites
                  _buildMultiValueSection(
                    _i18n.t('websites'),
                    _websiteControllers,
                    Icons.link,
                    TextInputType.url,
                    'https://example.com',
                  ),

                  // Social Handles
                  _buildSocialHandlesSection(),

                  // Locations
                  _buildLocationsSection(),

                  const SizedBox(height: 16),

                  // Notes
                  TextFormField(
                    controller: _notesController,
                    decoration: InputDecoration(
                      labelText: _i18n.t('notes'),
                      border: const OutlineInputBorder(),
                    ),
                    maxLines: 5,
                  ),

                  const SizedBox(height: 32),

                  // Save Button
                  FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_i18n.t('save')),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildMultiValueSection(
    String label,
    List<TextEditingController> controllers,
    IconData icon,
    TextInputType keyboardType,
    String hint,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(label, style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => _addField(controllers),
              tooltip: _i18n.t('add_another'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...List.generate(controllers.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: controllers[index],
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: hint,
                    ),
                    keyboardType: keyboardType,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: controllers.length > 1
                      ? () => _removeField(controllers, index)
                      : null,
                  color: Colors.red,
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSocialHandlesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.share, size: 20),
            const SizedBox(width: 8),
            Text(
              _i18n.t('social_handles'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: _addSocialHandle,
              tooltip: _i18n.t('add_another'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_socialHandleControllers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              _i18n.t('no_social_handles'),
              style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
            ),
          )
        else
          ...List.generate(_socialHandleControllers.length, (index) {
            final handle = _socialHandleControllers[index];
            final networkId = handle['network'] as String;
            final controller = handle['controller'] as TextEditingController;
            final network = _socialNetworks.firstWhere(
              (n) => n['id'] == networkId,
              orElse: () => {'id': networkId, 'name': networkId, 'prefix': ''},
            );

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: networkId,
                        decoration: InputDecoration(
                          labelText: _i18n.t('network'),
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        isExpanded: true,
                        items: _socialNetworks.map((n) {
                          return DropdownMenuItem(
                            value: n['id'],
                            child: Text(n['name']!, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _socialHandleControllers[index]['network'] = value;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: controller,
                        decoration: InputDecoration(
                          labelText: _i18n.t('handle'),
                          border: const OutlineInputBorder(),
                          hintText: network['prefix'],
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => _removeSocialHandle(index),
                      color: Colors.red,
                    ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 16),
      ],
    );
  }

  void _addSocialHandle() {
    setState(() {
      _socialHandleControllers.add({
        'network': 'x', // Default to X (Twitter)
        'controller': TextEditingController(),
      });
    });
  }

  void _removeSocialHandle(int index) {
    setState(() {
      final handle = _socialHandleControllers[index];
      (handle['controller'] as TextEditingController).dispose();
      _socialHandleControllers.removeAt(index);
    });
  }

  Widget _buildLocationsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.location_on, size: 20),
            const SizedBox(width: 8),
            Text(
              _i18n.t('typical_locations'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => _addField(_locationControllers),
              tooltip: _i18n.t('add_another'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...List.generate(_locationControllers.length, (index) {
          final controllers = _locationControllers[index];
          final locationType = controllers['type'] as String? ?? 'coordinates';
          final placePath = controllers['place'] as String?;

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Location name row with remove button
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: controllers['name'] as TextEditingController,
                          decoration: InputDecoration(
                            labelText: _i18n.t('location_name'),
                            border: const OutlineInputBorder(),
                            hintText: 'Home, Office, etc.',
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _locationControllers.length > 1
                            ? () => _removeField(_locationControllers, index)
                            : null,
                        color: Colors.red,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Location type dropdown
                  DropdownButtonFormField<String>(
                    value: locationType,
                    decoration: InputDecoration(
                      labelText: _i18n.t('location_type'),
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'coordinates',
                        child: Row(
                          children: [
                            const Icon(Icons.my_location, size: 20),
                            const SizedBox(width: 8),
                            Text(_i18n.t('coordinates')),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'place',
                        child: Row(
                          children: [
                            const Icon(Icons.place, size: 20),
                            const SizedBox(width: 8),
                            Text(_i18n.t('place')),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'online',
                        child: Row(
                          children: [
                            const Icon(Icons.videocam, size: 20),
                            const SizedBox(width: 8),
                            Text(_i18n.t('online')),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _locationControllers[index]['type'] = value;
                          if (value == 'online') {
                            (controllers['lat'] as TextEditingController).clear();
                            (controllers['long'] as TextEditingController).clear();
                            _locationControllers[index]['place'] = null;
                          } else if (value == 'coordinates') {
                            _locationControllers[index]['place'] = null;
                          } else if (value == 'place') {
                            (controllers['lat'] as TextEditingController).clear();
                            (controllers['long'] as TextEditingController).clear();
                          }
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),

                  // Location input based on type
                  if (locationType == 'coordinates') ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: controllers['lat'] as TextEditingController,
                            decoration: InputDecoration(
                              labelText: _i18n.t('location_coords'),
                              hintText: '40.7128,-74.0060',
                              border: const OutlineInputBorder(),
                              helperText: _i18n.t('enter_latitude_longitude'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton.filledTonal(
                          onPressed: () => _openMapPicker(index),
                          icon: const Icon(Icons.map),
                          tooltip: _i18n.t('select_on_map'),
                          iconSize: 24,
                          padding: const EdgeInsets.all(16),
                        ),
                      ],
                    ),
                  ] else if (locationType == 'place') ...[
                    OutlinedButton.icon(
                      onPressed: () => _openPlacePicker(index),
                      icon: const Icon(Icons.place_outlined, size: 18),
                      label: Text(_i18n.t('choose_place')),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    if (placePath != null) ...[
                      const SizedBox(height: 8),
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.place),
                          title: Text(placePath.split('/').last),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setState(() {
                                _locationControllers[index]['place'] = null;
                              });
                            },
                            tooltip: _i18n.t('remove'),
                          ),
                        ),
                      ),
                    ],
                  ],
                  // Online type shows nothing extra (just the name and type dropdown)
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _openMapPicker(int locationIndex) async {
    final result = await Navigator.push<LatLng>(
      context,
      MaterialPageRoute(
        builder: (context) => const LocationPickerPage(),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        // Store coordinates as lat,lon string
        final coordsText = '${result.latitude.toStringAsFixed(6)},${result.longitude.toStringAsFixed(6)}';
        (_locationControllers[locationIndex]['lat'] as TextEditingController).text = coordsText;
        (_locationControllers[locationIndex]['long'] as TextEditingController).clear();
      });

      // Try to get nearest city name
      final nearestCity = await LocationService().findNearestCity(
        result.latitude,
        result.longitude,
      );
      if (nearestCity != null && mounted) {
        final currentName = (_locationControllers[locationIndex]['name'] as TextEditingController).text;
        if (currentName.isEmpty) {
          setState(() {
            (_locationControllers[locationIndex]['name'] as TextEditingController).text =
                '${nearestCity.city}, ${nearestCity.country}';
          });
        }
      }
    }
  }

  Future<void> _openPlacePicker(int locationIndex) async {
    final selection = await showDialog<PlaceSelection>(
      context: context,
      builder: (context) => PlacePickerDialog(i18n: _i18n),
    );

    if (selection != null && mounted) {
      final place = selection.place;
      final langCode = _i18n.currentLanguage.split('_').first.toUpperCase();
      final placeName = place.getName(langCode);

      setState(() {
        _locationControllers[locationIndex]['place'] = place.folderPath;
        _locationControllers[locationIndex]['type'] = 'place';
        // Use place name if location name is empty
        final nameController = _locationControllers[locationIndex]['name'] as TextEditingController;
        if (nameController.text.isEmpty) {
          nameController.text = placeName;
        }
      });
    }
  }

  Widget _buildProfilePictureSection() {
    // Get current profile image
    ImageProvider? currentImage;
    if (!kIsWeb && _selectedProfilePicturePath != null) {
      currentImage = file_helper.getFileImageProvider(_selectedProfilePicturePath!);
    } else if (!kIsWeb && _existingProfilePicture != null && widget.collectionPath.isNotEmpty) {
      final path = _contactService.getProfilePicturePath(widget.contact?.callsign ?? '');
      if (path != null && file_helper.fileExists(path)) {
        currentImage = file_helper.getFileImageProvider(path);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.photo_camera, size: 20),
            const SizedBox(width: 8),
            Text(
              _i18n.t('profile_picture'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: Colors.grey.shade300,
              backgroundImage: currentImage,
              child: currentImage == null
                  ? Icon(Icons.person, size: 40, color: Colors.grey.shade600)
                  : null,
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.photo),
                  label: Text(_i18n.t('select_photo')),
                  onPressed: _pickProfilePicture,
                ),
                if (_selectedProfilePicturePath != null || _existingProfilePicture != null)
                  TextButton.icon(
                    icon: const Icon(Icons.delete, size: 18),
                    label: Text(_i18n.t('remove_photo')),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: _removeProfilePicture,
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickProfilePicture() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      dialogTitle: _i18n.t('select_profile_picture'),
    );

    if (result != null && result.files.isNotEmpty && result.files.first.path != null) {
      setState(() {
        _selectedProfilePicturePath = result.files.first.path;
      });
    }
  }

  void _removeProfilePicture() {
    setState(() {
      _selectedProfilePicturePath = null;
      _existingProfilePicture = null;
    });
  }

  Widget _buildTagsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.label, size: 20),
            const SizedBox(width: 8),
            Text(
              _i18n.t('tags'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            ..._tags.map((tag) => Chip(
                  label: Text(tag),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: () {
                    setState(() {
                      _tags.remove(tag);
                    });
                  },
                )),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: Text(_i18n.t('add_tag')),
              onPressed: _showAddTagDialog,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showAddTagDialog() async {
    final controller = TextEditingController();

    final tag = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_i18n.t('add_tag')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: _i18n.t('tag_name'),
            hintText: 'friend, work, family...',
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_i18n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(_i18n.t('add')),
          ),
        ],
      ),
    );

    if (tag != null && tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() {
        _tags.add(tag);
      });
    }
  }
}
