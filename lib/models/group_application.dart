/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'group_member.dart';

/// Application status
enum ApplicationStatus {
  pending,
  approved,
  rejected;

  static ApplicationStatus fromString(String value) {
    return ApplicationStatus.values.firstWhere(
      (e) => e.name.toLowerCase() == value.toLowerCase(),
      orElse: () => ApplicationStatus.pending,
    );
  }
}

/// Model representing a group membership application
class GroupApplication {
  final String filename;
  final String group;
  final String applicant;
  final String npub;
  final String applied;
  final ApplicationStatus status;
  final GroupRole requestedRole;
  final String? location;
  final String? experience;
  final List<String> references;
  final String introduction;
  final String signature;
  final String? decision;
  final String? decidedBy;
  final String? decidedByNpub;
  final String? decidedAt;
  final GroupRole? approvedRole;
  final String? decisionReason;
  final String? decisionSignature;

  GroupApplication({
    required this.filename,
    required this.group,
    required this.applicant,
    required this.npub,
    required this.applied,
    required this.status,
    required this.requestedRole,
    this.location,
    this.experience,
    this.references = const [],
    required this.introduction,
    required this.signature,
    this.decision,
    this.decidedBy,
    this.decidedByNpub,
    this.decidedAt,
    this.approvedRole,
    this.decisionReason,
    this.decisionSignature,
  });

  /// Parse applied timestamp to DateTime
  DateTime get appliedDateTime {
    try {
      final normalized = applied.replaceAll('_', ':');
      return DateTime.parse(normalized);
    } catch (e) {
      return DateTime.now();
    }
  }

  /// Parse decided timestamp to DateTime
  DateTime? get decidedDateTime {
    if (decidedAt == null) return null;
    try {
      final normalized = decidedAt!.replaceAll('_', ':');
      return DateTime.parse(normalized);
    } catch (e) {
      return null;
    }
  }

  /// Check if application has decision
  bool get hasDecision => decision != null && decision!.isNotEmpty;

  /// Check if application is pending
  bool get isPending => status == ApplicationStatus.pending;

  /// Check if application is approved
  bool get isApproved => status == ApplicationStatus.approved;

  /// Check if application is rejected
  bool get isRejected => status == ApplicationStatus.rejected;

  /// Get reference count
  int get referenceCount => references.length;

  /// Parse application from text file
  static GroupApplication fromText(String text, String filename) {
    final lines = text.split('\n');
    if (lines.isEmpty) {
      throw Exception('Empty application file');
    }

    String? group;
    String? applicant;
    String? npub;
    String? applied;
    ApplicationStatus status = ApplicationStatus.pending;
    GroupRole requestedRole = GroupRole.guest;
    String? location;
    String? experience;
    List<String> references = [];
    String introduction = '';
    String? signature;

    // Decision fields
    String? decision;
    String? decidedBy;
    String? decidedByNpub;
    String? decidedAt;
    GroupRole? approvedRole;
    String? decisionReason;
    String? decisionSignature;

    bool inReferences = false;
    bool inIntroduction = false;
    bool inDecisionRecord = false;
    final introLines = <String>[];
    final decisionReasonLines = <String>[];

    for (var line in lines) {
      final trimmed = line.trim();

      // Check for section markers
      if (trimmed == '---' || trimmed.startsWith('--- DECISION RECORD')) {
        if (inIntroduction) {
          inIntroduction = false;
          introduction = introLines.join('\n').trim();
        }
        if (trimmed.startsWith('--- DECISION RECORD')) {
          inDecisionRecord = true;
        }
        continue;
      }

      // Parse key-value pairs
      if (line.contains(':') && !line.startsWith('-')) {
        final colonIndex = line.indexOf(':');
        final key = line.substring(0, colonIndex).trim().toLowerCase();
        final value = line.substring(colonIndex + 1).trim();

        if (!inDecisionRecord) {
          switch (key) {
            case 'group':
              group = value;
              break;
            case 'applicant':
              applicant = value;
              break;
            case 'npub':
              npub = value;
              break;
            case 'applied':
              applied = value;
              break;
            case 'status':
              status = ApplicationStatus.fromString(value);
              break;
            case 'requested_role':
              requestedRole = GroupRole.fromString(value);
              break;
            case 'location':
              location = value;
              break;
            case 'experience':
              experience = value;
              break;
            case 'references':
              inReferences = true;
              continue;
            case 'introduction':
              inIntroduction = true;
              inReferences = false;
              continue;
            case 'signature':
              signature = value;
              inIntroduction = false;
              break;
          }
        } else {
          // Decision record section
          switch (key) {
            case 'decision':
              decision = value;
              break;
            case 'decided_by':
              decidedBy = value;
              break;
            case 'decided_by_npub':
              decidedByNpub = value;
              break;
            case 'decided_at':
              decidedAt = value;
              break;
            case 'approved_role':
              if (value.toLowerCase() != 'null') {
                approvedRole = GroupRole.fromString(value);
              }
              break;
            case 'decision_reason':
              // Multi-line decision reason starts here
              continue;
            case 'decision_signature':
              decisionSignature = value;
              break;
          }
        }
      } else if (inReferences && line.startsWith('- ')) {
        references.add(line.substring(2).trim());
      } else if (inIntroduction && trimmed.isNotEmpty) {
        introLines.add(line);
      } else if (inDecisionRecord && line.isNotEmpty && !line.contains(':')) {
        decisionReasonLines.add(line);
      }
    }

    // Assemble decision reason from collected lines
    if (decisionReasonLines.isNotEmpty) {
      decisionReason = decisionReasonLines.join('\n').trim();
    }

    // Validate required fields
    if (group == null || applicant == null || npub == null || applied == null || signature == null) {
      throw Exception('Missing required application fields');
    }

    return GroupApplication(
      filename: filename,
      group: group,
      applicant: applicant,
      npub: npub,
      applied: applied,
      status: status,
      requestedRole: requestedRole,
      location: location,
      experience: experience,
      references: references,
      introduction: introduction,
      signature: signature,
      decision: decision,
      decidedBy: decidedBy,
      decidedByNpub: decidedByNpub,
      decidedAt: decidedAt,
      approvedRole: approvedRole,
      decisionReason: decisionReason,
      decisionSignature: decisionSignature,
    );
  }

  /// Export application as text
  String exportAsText() {
    final buffer = StringBuffer();

    buffer.writeln('group: $group');
    buffer.writeln('applicant: $applicant');
    buffer.writeln('npub: $npub');
    buffer.writeln('applied: $applied');
    buffer.writeln('status: ${status.name}');
    buffer.writeln('requested_role: ${requestedRole.name}');

    if (location != null && location!.isNotEmpty) {
      buffer.writeln('location: $location');
    }

    if (experience != null && experience!.isNotEmpty) {
      buffer.writeln('experience: $experience');
    }

    buffer.writeln();

    if (references.isNotEmpty) {
      buffer.writeln('references:');
      for (var ref in references) {
        buffer.writeln('- $ref');
      }
      buffer.writeln();
    }

    buffer.writeln('introduction:');
    buffer.writeln(introduction);
    buffer.writeln();

    buffer.writeln('signature: $signature');

    if (hasDecision) {
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln('DECISION RECORD');
      buffer.writeln('---');
      buffer.writeln();
      buffer.writeln('decision: $decision');
      buffer.writeln('decided_by: $decidedBy');
      buffer.writeln('decided_by_npub: $decidedByNpub');
      buffer.writeln('decided_at: $decidedAt');
      buffer.writeln('approved_role: ${approvedRole?.name ?? 'null'}');
      buffer.writeln('decision_reason: $decisionReason');
      if (decisionSignature != null) {
        buffer.writeln('decision_signature: $decisionSignature');
      }
    }

    return buffer.toString();
  }

  /// Create copy with updated fields
  GroupApplication copyWith({
    String? filename,
    String? group,
    String? applicant,
    String? npub,
    String? applied,
    ApplicationStatus? status,
    GroupRole? requestedRole,
    String? location,
    String? experience,
    List<String>? references,
    String? introduction,
    String? signature,
    String? decision,
    String? decidedBy,
    String? decidedByNpub,
    String? decidedAt,
    GroupRole? approvedRole,
    String? decisionReason,
    String? decisionSignature,
  }) {
    return GroupApplication(
      filename: filename ?? this.filename,
      group: group ?? this.group,
      applicant: applicant ?? this.applicant,
      npub: npub ?? this.npub,
      applied: applied ?? this.applied,
      status: status ?? this.status,
      requestedRole: requestedRole ?? this.requestedRole,
      location: location ?? this.location,
      experience: experience ?? this.experience,
      references: references ?? this.references,
      introduction: introduction ?? this.introduction,
      signature: signature ?? this.signature,
      decision: decision ?? this.decision,
      decidedBy: decidedBy ?? this.decidedBy,
      decidedByNpub: decidedByNpub ?? this.decidedByNpub,
      decidedAt: decidedAt ?? this.decidedAt,
      approvedRole: approvedRole ?? this.approvedRole,
      decisionReason: decisionReason ?? this.decisionReason,
      decisionSignature: decisionSignature ?? this.decisionSignature,
    );
  }

  @override
  String toString() {
    return 'GroupApplication(applicant: $applicant, status: ${status.name}, requestedRole: ${requestedRole.name})';
  }
}
