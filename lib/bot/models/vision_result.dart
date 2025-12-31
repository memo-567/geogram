/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

/// Result of image analysis by vision models
class VisionResult {
  /// Natural language description of the image
  final String? description;

  /// Detected objects with bounding boxes
  final List<DetectedObject> objects;

  /// Extracted text from OCR
  final String? extractedText;

  /// Transliteration of extracted text (e.g., Cyrillic to Latin)
  final String? transliteration;

  /// Translation of extracted text
  final String? translation;

  /// Classification labels (e.g., "cat", "dog", "car")
  final List<String> labels;

  /// Plant/species identification result
  final SpeciesIdentification? species;

  /// Overall confidence score (0.0 - 1.0)
  final double confidence;

  /// Which model produced this result
  final String modelUsed;

  /// Processing time in milliseconds
  final int processingTimeMs;

  const VisionResult({
    this.description,
    this.objects = const [],
    this.extractedText,
    this.transliteration,
    this.translation,
    this.labels = const [],
    this.species,
    this.confidence = 0.0,
    required this.modelUsed,
    this.processingTimeMs = 0,
  });

  /// Check if this result has any useful content
  bool get hasContent =>
      description != null ||
      objects.isNotEmpty ||
      extractedText != null ||
      labels.isNotEmpty ||
      species != null;

  Map<String, dynamic> toJson() => {
        if (description != null) 'description': description,
        if (objects.isNotEmpty)
          'objects': objects.map((o) => o.toJson()).toList(),
        if (extractedText != null) 'extractedText': extractedText,
        if (transliteration != null) 'transliteration': transliteration,
        if (translation != null) 'translation': translation,
        if (labels.isNotEmpty) 'labels': labels,
        if (species != null) 'species': species!.toJson(),
        'confidence': confidence,
        'modelUsed': modelUsed,
        'processingTimeMs': processingTimeMs,
      };

  factory VisionResult.fromJson(Map<String, dynamic> json) {
    return VisionResult(
      description: json['description'] as String?,
      objects: (json['objects'] as List<dynamic>?)
              ?.map((o) => DetectedObject.fromJson(o as Map<String, dynamic>))
              .toList() ??
          [],
      extractedText: json['extractedText'] as String?,
      transliteration: json['transliteration'] as String?,
      translation: json['translation'] as String?,
      labels: (json['labels'] as List<dynamic>?)?.cast<String>() ?? [],
      species: json['species'] != null
          ? SpeciesIdentification.fromJson(
              json['species'] as Map<String, dynamic>)
          : null,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      modelUsed: json['modelUsed'] as String? ?? 'unknown',
      processingTimeMs: json['processingTimeMs'] as int? ?? 0,
    );
  }
}

/// A detected object in an image with bounding box
class DetectedObject {
  /// Classification label (e.g., "person", "car", "dog")
  final String label;

  /// Confidence score (0.0 - 1.0)
  final double confidence;

  /// Bounding box in normalized coordinates (0.0 - 1.0)
  final BoundingBox boundingBox;

  const DetectedObject({
    required this.label,
    required this.confidence,
    required this.boundingBox,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'confidence': confidence,
        'boundingBox': boundingBox.toJson(),
      };

  factory DetectedObject.fromJson(Map<String, dynamic> json) {
    return DetectedObject(
      label: json['label'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      boundingBox: BoundingBox.fromJson(json['boundingBox'] as Map<String, dynamic>),
    );
  }
}

/// Bounding box for detected objects (normalized coordinates 0.0 - 1.0)
class BoundingBox {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const BoundingBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  const BoundingBox.fromLTRB(this.left, this.top, this.right, this.bottom);

  double get width => right - left;
  double get height => bottom - top;

  Map<String, dynamic> toJson() => {
        'left': left,
        'top': top,
        'right': right,
        'bottom': bottom,
      };

  factory BoundingBox.fromJson(Map<String, dynamic> json) {
    return BoundingBox(
      left: (json['left'] as num).toDouble(),
      top: (json['top'] as num).toDouble(),
      right: (json['right'] as num).toDouble(),
      bottom: (json['bottom'] as num).toDouble(),
    );
  }

  @override
  String toString() => 'BoundingBox($left, $top, $right, $bottom)';
}

/// Plant or species identification result
class SpeciesIdentification {
  /// Scientific name (e.g., "Amanita muscaria")
  final String scientificName;

  /// Common name (e.g., "Fly Agaric")
  final String? commonName;

  /// Taxonomy (kingdom, phylum, class, order, family, genus)
  final Map<String, String> taxonomy;

  /// Whether this species is known to be toxic/dangerous
  final bool isToxic;

  /// Warning message if applicable
  final String? warning;

  /// Confidence score (0.0 - 1.0)
  final double confidence;

  /// Brief description of identifying features
  final String? description;

  const SpeciesIdentification({
    required this.scientificName,
    this.commonName,
    this.taxonomy = const {},
    this.isToxic = false,
    this.warning,
    required this.confidence,
    this.description,
  });

  Map<String, dynamic> toJson() => {
        'scientificName': scientificName,
        if (commonName != null) 'commonName': commonName,
        if (taxonomy.isNotEmpty) 'taxonomy': taxonomy,
        'isToxic': isToxic,
        if (warning != null) 'warning': warning,
        'confidence': confidence,
        if (description != null) 'description': description,
      };

  factory SpeciesIdentification.fromJson(Map<String, dynamic> json) {
    return SpeciesIdentification(
      scientificName: json['scientificName'] as String,
      commonName: json['commonName'] as String?,
      taxonomy: (json['taxonomy'] as Map<String, dynamic>?)?.cast<String, String>() ?? {},
      isToxic: json['isToxic'] as bool? ?? false,
      warning: json['warning'] as String?,
      confidence: (json['confidence'] as num).toDouble(),
      description: json['description'] as String?,
    );
  }
}
