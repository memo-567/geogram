/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:math';

import 'package:flutter/material.dart';

/// Animated equalizer bars widget that shows audio visualization
class AnimatedEqualizerWidget extends StatefulWidget {
  final double size;
  final Color color;
  final bool isPlaying;
  final int barCount;

  const AnimatedEqualizerWidget({
    super.key,
    this.size = 24,
    required this.color,
    this.isPlaying = true,
    this.barCount = 3,
  });

  @override
  State<AnimatedEqualizerWidget> createState() => _AnimatedEqualizerWidgetState();
}

class _AnimatedEqualizerWidgetState extends State<AnimatedEqualizerWidget>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  void _initAnimations() {
    _controllers = List.generate(widget.barCount, (index) {
      return AnimationController(
        duration: Duration(milliseconds: 300 + _random.nextInt(200)),
        vsync: this,
      );
    });

    _animations = _controllers.map((controller) {
      return Tween<double>(begin: 0.2, end: 1.0).animate(
        CurvedAnimation(
          parent: controller,
          curve: Curves.easeInOut,
        ),
      );
    }).toList();

    if (widget.isPlaying) {
      _startAnimations();
    }
  }

  void _startAnimations() {
    for (int i = 0; i < _controllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 100), () {
        if (mounted && widget.isPlaying) {
          _controllers[i].repeat(reverse: true);
        }
      });
    }
  }

  void _stopAnimations() {
    for (final controller in _controllers) {
      controller.stop();
      controller.animateTo(0.3, duration: const Duration(milliseconds: 200));
    }
  }

  @override
  void didUpdateWidget(AnimatedEqualizerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _startAnimations();
      } else {
        _stopAnimations();
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final barWidth = widget.size / (widget.barCount * 2);
    final spacing = barWidth * 0.5;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(widget.barCount, (index) {
          return AnimatedBuilder(
            animation: _animations[index],
            builder: (context, child) {
              return Container(
                width: barWidth,
                height: widget.size * _animations[index].value * 0.8,
                margin: EdgeInsets.symmetric(horizontal: spacing / 2),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(barWidth / 2),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
