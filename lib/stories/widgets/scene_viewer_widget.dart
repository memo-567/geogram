/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/story.dart';
import '../models/story_scene.dart';
import '../models/story_element.dart';
import '../models/story_trigger.dart';
import '../services/stories_storage_service.dart';
import 'story_element_widget.dart';

/// Widget that renders a scene with its background, elements, and handles timing
class SceneViewerWidget extends StatefulWidget {
  final StoryScene scene;
  final Story story;
  final StoriesStorageService storage;
  final Function(StoryTrigger) onTrigger;
  final bool isEditing;

  const SceneViewerWidget({
    super.key,
    required this.scene,
    required this.story,
    required this.storage,
    required this.onTrigger,
    this.isEditing = false,
  });

  @override
  State<SceneViewerWidget> createState() => _SceneViewerWidgetState();
}

class _SceneViewerWidgetState extends State<SceneViewerWidget> {
  String? _backgroundImagePath;
  bool _showBackground = false;
  final Map<String, bool> _visibleElements = {};
  Timer? _timingTimer;
  int _elapsedMs = 0;

  @override
  void initState() {
    super.initState();
    _loadBackground();
    _startTiming();
  }

  @override
  void didUpdateWidget(SceneViewerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scene.id != widget.scene.id) {
      // Scene changed, reset everything
      _backgroundImagePath = null;
      _showBackground = false;
      _visibleElements.clear();
      _elapsedMs = 0;
      _loadBackground();
      _startTiming();
    }
  }

  @override
  void dispose() {
    _timingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBackground() async {
    if (widget.scene.background.asset != null) {
      final path = await widget.storage.extractMedia(
        widget.story,
        widget.scene.background.asset!,
      );
      if (mounted && path != null) {
        setState(() => _backgroundImagePath = path);
      }
    }
  }

  void _startTiming() {
    _timingTimer?.cancel();
    _elapsedMs = 0;

    // Check initial visibility
    _updateVisibility();

    // Start timer for timed elements
    _timingTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      _elapsedMs += 50;
      _updateVisibility();

      // Stop when all elements are visible
      if (_allElementsVisible()) {
        timer.cancel();
      }
    });
  }

  void _updateVisibility() {
    setState(() {
      // Background visibility
      _showBackground = _elapsedMs >= widget.scene.background.appearAt;

      // Element visibility
      for (final element in widget.scene.elements) {
        _visibleElements[element.id] = _elapsedMs >= element.appearAt;
      }
    });
  }

  bool _allElementsVisible() {
    if (!_showBackground && widget.scene.background.appearAt > 0) return false;

    for (final element in widget.scene.elements) {
      if (!(_visibleElements[element.id] ?? false)) return false;
    }
    return true;
  }

  void _handleElementTap(StoryElement element) {
    final trigger = widget.scene.getTriggerForElement(element.id);
    if (trigger != null) {
      widget.onTrigger(trigger);
    }
  }

  void _handleTouchAreaTap(TouchArea area) {
    final triggers = widget.scene.touchAreaTriggers;
    for (final trigger in triggers) {
      if (trigger.touchArea == area) {
        widget.onTrigger(trigger);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            // Background
            _buildBackground(constraints),

            // Touch areas (invisible but tappable)
            ..._buildTouchAreas(constraints),

            // Elements
            ..._buildElements(constraints),
          ],
        );
      },
    );
  }

  Widget _buildBackground(BoxConstraints constraints) {
    final bg = widget.scene.background;
    final placeholderColor = _parseColor(bg.placeholder);

    if (!_showBackground) {
      return Container(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        color: placeholderColor,
      );
    }

    // Always use cover to ensure consistent element positioning across orientations
    const fit = BoxFit.cover;

    return AnimatedOpacity(
      opacity: _showBackground ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        color: placeholderColor,
        child: _backgroundImagePath != null
            ? Image.file(
                File(_backgroundImagePath!),
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                fit: fit,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  List<Widget> _buildTouchAreas(BoxConstraints constraints) {
    final triggers = widget.scene.touchAreaTriggers;
    if (triggers.isEmpty) return [];

    return triggers.map((trigger) {
      if (trigger.touchArea == null) return const SizedBox.shrink();

      final rect = _getTouchAreaRect(trigger.touchArea!, constraints);
      return Positioned(
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
        child: GestureDetector(
          onTap: () => _handleTouchAreaTap(trigger.touchArea!),
          behavior: HitTestBehavior.opaque,
          child: Container(
            color: Colors.transparent,
          ),
        ),
      );
    }).toList();
  }

  Rect _getTouchAreaRect(TouchArea area, BoxConstraints constraints) {
    final w = constraints.maxWidth;
    final h = constraints.maxHeight;

    switch (area) {
      case TouchArea.leftHalf:
        return Rect.fromLTWH(0, 0, w / 2, h);
      case TouchArea.rightHalf:
        return Rect.fromLTWH(w / 2, 0, w / 2, h);
      case TouchArea.topHalf:
        return Rect.fromLTWH(0, 0, w, h / 2);
      case TouchArea.bottomHalf:
        return Rect.fromLTWH(0, h / 2, w, h / 2);
      case TouchArea.topLeft:
        return Rect.fromLTWH(0, 0, w / 2, h / 2);
      case TouchArea.topRight:
        return Rect.fromLTWH(w / 2, 0, w / 2, h / 2);
      case TouchArea.bottomLeft:
        return Rect.fromLTWH(0, h / 2, w / 2, h / 2);
      case TouchArea.bottomRight:
        return Rect.fromLTWH(w / 2, h / 2, w / 2, h / 2);
      case TouchArea.center:
        return Rect.fromLTWH(w / 4, h / 4, w / 2, h / 2);
    }
  }

  List<Widget> _buildElements(BoxConstraints constraints) {
    final w = constraints.maxWidth;
    final h = constraints.maxHeight;

    return widget.scene.elements.map((element) {
      final isVisible = _visibleElements[element.id] ?? false;

      // Calculate position
      final position = element.position;
      final (left, top) = position.calculatePosition();
      final leftPx = (left / 100) * w;
      final topPx = (top / 100) * h;
      final widthPx = position.widthPercent > 0 ? (position.widthPercent / 100) * w : null;
      final heightPx = position.heightPercent != null ? (position.heightPercent! / 100) * h : null;

      return Positioned(
        left: leftPx,
        top: topPx,
        width: widthPx,
        height: heightPx,
        child: AnimatedOpacity(
          opacity: isVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: StoryElementWidget(
            element: element,
            story: widget.story,
            storage: widget.storage,
            constraints: constraints,
            onTap: isVisible ? () => _handleElementTap(element) : null,
            isEditing: widget.isEditing,
          ),
        ),
      );
    }).toList();
  }

  Color _parseColor(String colorString) {
    if (colorString.startsWith('#')) {
      final hex = colorString.substring(1);
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      } else if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    } else if (colorString.startsWith('rgba')) {
      // Parse rgba(r, g, b, a) format
      final match = RegExp(r'rgba\((\d+),\s*(\d+),\s*(\d+),\s*([\d.]+)\)')
          .firstMatch(colorString);
      if (match != null) {
        return Color.fromRGBO(
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
          int.parse(match.group(3)!),
          double.parse(match.group(4)!),
        );
      }
    }
    return Colors.black;
  }
}
