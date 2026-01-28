/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'package:flutter/material.dart';

import '../../models/presentation_content.dart';
import 'slide_canvas_widget.dart';

/// Thumbnail widget for displaying a slide preview in the slide panel
class SlideThumbnailWidget extends StatelessWidget {
  final PresentationSlide slide;
  final PresentationTheme theme;
  final SlideTemplate? template;
  final double aspectRatio;
  final bool isSelected;
  final int slideNumber;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final ImageLoader? imageLoader;

  const SlideThumbnailWidget({
    super.key,
    required this.slide,
    required this.theme,
    this.template,
    this.aspectRatio = 16 / 9,
    this.isSelected = false,
    required this.slideNumber,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.imageLoader,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Slide number label
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                '$slideNumber',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            // Slide preview
            ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(3),
                bottomRight: Radius.circular(3),
              ),
              child: AbsorbPointer(
                child: SlideCanvasWidget(
                  slide: slide,
                  theme: theme,
                  template: template,
                  aspectRatio: aspectRatio,
                  imageLoader: imageLoader,
                  isEditing: false,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A draggable slide thumbnail for reordering
class DraggableSlideThumbnail extends StatelessWidget {
  final PresentationSlide slide;
  final PresentationTheme theme;
  final SlideTemplate? template;
  final double aspectRatio;
  final bool isSelected;
  final int slideNumber;
  final int index;
  final VoidCallback? onTap;
  final ImageLoader? imageLoader;

  const DraggableSlideThumbnail({
    super.key,
    required this.slide,
    required this.theme,
    this.template,
    this.aspectRatio = 16 / 9,
    this.isSelected = false,
    required this.slideNumber,
    required this.index,
    this.onTap,
    this.imageLoader,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ReorderableDragStartListener(
      index: index,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          key: ValueKey(slide.id),
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Slide number with drag handle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    Text(
                      '$slideNumber',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.drag_handle,
                      size: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              // Slide preview
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(3),
                  bottomRight: Radius.circular(3),
                ),
                child: AbsorbPointer(
                  child: SlideCanvasWidget(
                    slide: slide,
                    theme: theme,
                    template: template,
                    aspectRatio: aspectRatio,
                    imageLoader: imageLoader,
                    isEditing: false,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
