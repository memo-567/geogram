#!/usr/bin/env dart
/*
 * Feedback Race Condition Test
 *
 * Tests that file locking prevents duplicate feedback when
 * multiple concurrent requests attempt to add feedback from the same user.
 *
 * This test validates the fix for the race condition vulnerability
 * where concurrent requests could inflate feedback counts.
 */

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import '../lib/util/feedback_folder_utils.dart';
import '../lib/util/nostr_event.dart';
import '../lib/util/nostr_crypto.dart';

// ANSI color codes
const String green = '\x1B[32m';
const String red = '\x1B[31m';
const String yellow = '\x1B[33m';
const String blue = '\x1B[34m';
const String reset = '\x1B[0m';

void pass(String test) {
  print('${green}✓ PASS${reset} $test');
}

void fail(String test, String reason) {
  print('${red}✗ FAIL${reset} $test: $reason');
  exit(1);
}

void info(String message) {
  print('${blue}ℹ${reset} $message');
}

void section(String name) {
  print('\n${yellow}━━━ $name ━━━${reset}');
}

/// Create a test NOSTR keypair
NostrKeyPair generateTestKeypair() {
  return NostrCrypto.generateKeyPair();
}

/// Create a signed feedback event
NostrEvent createFeedbackEvent(String npub, String nsec, String postId) {
  final pubkeyHex = NostrCrypto.decodeNpub(npub);
  final event = NostrEvent(
    pubkey: pubkeyHex,
    createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    kind: NostrEventKind.reaction,
    tags: [
      ['e', postId],
      ['type', 'like'],
    ],
    content: 'like',
  );

  event.calculateId();
  event.signWithNsec(nsec);

  return event;
}

/// Test concurrent duplicate feedback prevention
Future<void> testConcurrentDuplicatePrevention() async {
  section('Test: Concurrent Duplicate Prevention');

  // Create temp directory
  final testDir = Directory.systemTemp.createTempSync('feedback_race_test_');
  final contentPath = testDir.path;
  info('Test directory: $contentPath');

  try {
    // Generate test keypair
    final keypair = generateTestKeypair();
    final npub = keypair.npub;
    final nsec = keypair.nsec;
    info('Generated test npub: ${npub.substring(0, 20)}...');

    // Create feedback folder first
    await FeedbackFolderUtils.ensureFeedbackFolder(contentPath);

    // Launch 10 concurrent requests to add the same user's like
    info('Launching 10 concurrent duplicate like requests...');
    final futures = <Future<bool>>[];

    for (int i = 0; i < 10; i++) {
      final event = createFeedbackEvent(npub, nsec, 'test-post-123');

      // Debug: verify event is signed correctly
      if (!event.verify()) {
        fail('Event creation', 'Event $i failed signature verification');
      }

      final future = FeedbackFolderUtils.addFeedbackEvent(
        contentPath,
        FeedbackFolderUtils.feedbackTypeLikes,
        event,
      );
      futures.add(future);
    }

    // Wait for all to complete
    final results = await Future.wait(futures);

    // Count successes
    final successCount = results.where((r) => r == true).length;
    info('Successful adds: $successCount out of 10');

    // Verify only ONE succeeded (race condition prevented)
    if (successCount != 1) {
      fail(
        'Concurrent duplicate prevention',
        'Expected exactly 1 success, got $successCount (race condition not prevented!)',
      );
    }
    pass('Only 1 out of 10 concurrent requests succeeded');

    // Verify file contains exactly one npub
    final npubs = await FeedbackFolderUtils.readFeedbackFile(
      contentPath,
      FeedbackFolderUtils.feedbackTypeLikes,
    );

    if (npubs.length != 1) {
      fail(
        'File integrity check',
        'Expected 1 npub in file, found ${npubs.length}',
      );
    }
    pass('File contains exactly 1 npub (no duplicates)');

    // Verify count is correct
    final count = await FeedbackFolderUtils.getFeedbackCount(
      contentPath,
      FeedbackFolderUtils.feedbackTypeLikes,
    );

    if (count != 1) {
      fail(
        'Count verification',
        'Expected count=1, got count=$count',
      );
    }
    pass('Feedback count is correct: 1');

  } finally {
    // Cleanup
    await testDir.delete(recursive: true);
  }
}

/// Test toggle race condition
Future<void> testToggleRaceCondition() async {
  section('Test: Toggle Race Condition Prevention');

  // Create temp directory
  final testDir = Directory.systemTemp.createTempSync('feedback_toggle_test_');
  final contentPath = testDir.path;
  info('Test directory: $contentPath');

  try {
    // Generate test keypair
    final keypair = generateTestKeypair();
    final npub = keypair.npub;
    final nsec = keypair.nsec;
    info('Generated test npub: ${npub.substring(0, 20)}...');

    // Create feedback folder first
    await FeedbackFolderUtils.ensureFeedbackFolder(contentPath);

    // Launch 20 concurrent toggle requests
    info('Launching 20 concurrent toggle requests...');
    final futures = <Future<bool?>>[];

    for (int i = 0; i < 20; i++) {
      final event = createFeedbackEvent(npub, nsec, 'test-post-456');
      final future = FeedbackFolderUtils.toggleFeedbackEvent(
        contentPath,
        FeedbackFolderUtils.feedbackTypeLikes,
        event,
      );
      futures.add(future);
    }

    // Wait for all to complete
    final results = await Future.wait(futures);

    // Count true (added) and false (removed)
    final addCount = results.where((r) => r == true).length;
    final removeCount = results.where((r) => r == false).length;
    info('Toggles: $addCount added, $removeCount removed');

    // Final state should be either 0 or 1 npubs (depending on even/odd successful toggles)
    final npubs = await FeedbackFolderUtils.readFeedbackFile(
      contentPath,
      FeedbackFolderUtils.feedbackTypeLikes,
    );

    if (npubs.length > 1) {
      fail(
        'Toggle race condition',
        'Expected 0 or 1 npub in file, found ${npubs.length} (duplicates detected!)',
      );
    }
    pass('Toggle resulted in ${npubs.length} npub(s) - no duplicates');

    // Verify count matches
    final count = await FeedbackFolderUtils.getFeedbackCount(
      contentPath,
      FeedbackFolderUtils.feedbackTypeLikes,
    );

    if (count != npubs.length) {
      fail(
        'Count mismatch',
        'Count ($count) does not match npub list length (${npubs.length})',
      );
    }
    pass('Feedback count matches: $count');

  } finally {
    // Cleanup
    await testDir.delete(recursive: true);
  }
}

/// Test different users can add feedback simultaneously
Future<void> testMultipleUsersConcurrent() async {
  section('Test: Multiple Users Concurrent Feedback');

  // Create temp directory
  final testDir = Directory.systemTemp.createTempSync('feedback_multi_test_');
  final contentPath = testDir.path;
  info('Test directory: $contentPath');

  try {
    // Generate 5 different keypairs
    final keypairs = List.generate(5, (_) => generateTestKeypair());
    info('Generated 5 test users');

    // Create feedback folder first
    await FeedbackFolderUtils.ensureFeedbackFolder(contentPath);

    // Each user adds feedback concurrently
    final futures = <Future<bool>>[];

    for (final keypair in keypairs) {
      final event = createFeedbackEvent(
        keypair.npub,
        keypair.nsec,
        'test-post-789',
      );
      final future = FeedbackFolderUtils.addFeedbackEvent(
        contentPath,
        FeedbackFolderUtils.feedbackTypeLikes,
        event,
      );
      futures.add(future);
    }

    // Wait for all to complete
    final results = await Future.wait(futures);

    // All should succeed
    final successCount = results.where((r) => r == true).length;
    info('Successful adds: $successCount out of 5');

    if (successCount != 5) {
      fail(
        'Multiple users concurrent',
        'Expected all 5 users to succeed, got $successCount',
      );
    }
    pass('All 5 users successfully added feedback concurrently');

    // Verify file contains exactly 5 unique npubs
    final npubs = await FeedbackFolderUtils.readFeedbackFile(
      contentPath,
      FeedbackFolderUtils.feedbackTypeLikes,
    );

    if (npubs.length != 5) {
      fail(
        'Multiple users verification',
        'Expected 5 npubs in file, found ${npubs.length}',
      );
    }
    pass('File contains exactly 5 unique npubs');

    // Verify all npubs are unique
    final uniqueNpubs = npubs.toSet();
    if (uniqueNpubs.length != 5) {
      fail(
        'Uniqueness check',
        'Found duplicate npubs: ${npubs.length} total, ${uniqueNpubs.length} unique',
      );
    }
    pass('All npubs are unique');

  } finally {
    // Cleanup
    await testDir.delete(recursive: true);
  }
}

/// Main test runner
Future<void> main() async {
  print('\n${yellow}╔════════════════════════════════════════════════════════╗${reset}');
  print('${yellow}║   Feedback Race Condition Prevention Test Suite       ║${reset}');
  print('${yellow}╚════════════════════════════════════════════════════════╝${reset}\n');

  info('Testing file locking prevents duplicate feedback');
  info('This validates the fix for concurrent request race conditions\n');

  try {
    // Run tests
    await testConcurrentDuplicatePrevention();
    await testToggleRaceCondition();
    await testMultipleUsersConcurrent();

    // Success
    print('\n${green}╔════════════════════════════════════════════════════════╗${reset}');
    print('${green}║   ✓ ALL TESTS PASSED                                   ║${reset}');
    print('${green}╚════════════════════════════════════════════════════════╝${reset}\n');

    print('${green}Race condition vulnerability has been successfully mitigated.${reset}');
    print('${green}File locking ensures atomic read-modify-write operations.${reset}\n');

    exit(0);
  } catch (e) {
    print('\n${red}╔════════════════════════════════════════════════════════╗${reset}');
    print('${red}║   ✗ TEST SUITE FAILED                                  ║${reset}');
    print('${red}╚════════════════════════════════════════════════════════╝${reset}\n');
    print('${red}Error: $e${reset}\n');
    exit(1);
  }
}
