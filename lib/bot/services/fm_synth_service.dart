/*
 * Copyright (c) geogram
 * License: Apache-2.0
 */

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../models/music_track.dart';
import '../models/music_model_info.dart';
import 'music_storage_service.dart';
import '../../services/log_service.dart';

/// FM Synthesis service for instant procedural music generation.
/// Works on all devices without any model downloads.
class FMSynthService {
  static final FMSynthService _instance = FMSynthService._internal();
  factory FMSynthService() => _instance;
  FMSynthService._internal();

  /// Sample rate for generated audio
  static const int sampleRate = 44100;

  /// Generate a complete music track using FM synthesis.
  /// Returns a MusicTrack with the generated audio saved to storage.
  Future<MusicTrack> generate({
    required String genre,
    required Duration duration,
    required String prompt,
  }) async {
    final stopwatch = Stopwatch()..start();

    LogService().log(
        'FMSynthService: Generating $genre music for ${duration.inSeconds}s');

    // Get genre preset
    final preset = _getGenrePreset(genre);

    // Generate PCM samples
    final samples = _generateMusic(preset, duration);

    // Convert to WAV format
    final wavData = _createWavFile(samples);

    // Create track metadata
    final trackId =
        'fm_${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(10000)}';
    final track = MusicTrack(
      id: trackId,
      filePath: '', // Will be updated after saving
      genre: genre,
      prompt: prompt,
      duration: duration,
      createdAt: DateTime.now(),
      modelUsed: 'fm-synth',
      isFMFallback: false,
      stats: MusicGenerationStats(
        processingTimeMs: stopwatch.elapsedMilliseconds,
        qualityLevel: 'procedural',
      ),
    );

    // Save to storage
    final storage = MusicStorageService();
    final filePath = await storage.saveTrack(track, wavData);

    stopwatch.stop();
    LogService().log(
        'FMSynthService: Generated ${(wavData.length / 1024).toStringAsFixed(0)} KB in ${stopwatch.elapsedMilliseconds}ms');

    return track.copyWith(filePath: filePath);
  }

  /// Generate raw PCM samples (Float32) without saving.
  /// Useful for streaming playback.
  Float32List generateRawSamples({
    required String genre,
    required Duration duration,
  }) {
    final preset = _getGenrePreset(genre);
    return _generateMusic(preset, duration);
  }

  final _random = Random();

  /// Generate music samples using FM synthesis
  Float32List _generateMusic(_GenrePreset preset, Duration duration) {
    final numSamples = (duration.inMilliseconds * sampleRate / 1000).round();
    final samples = Float32List(numSamples);

    // Initialize oscillators
    final oscillators = <_Oscillator>[];
    for (var i = 0; i < preset.numVoices; i++) {
      oscillators.add(_Oscillator(
        baseFreq: preset.baseFrequencies[i % preset.baseFrequencies.length],
        modRatio: preset.modRatios[i % preset.modRatios.length],
        modIndex: preset.modIndex,
        sampleRate: sampleRate,
      ));
    }

    // Initialize drum machine
    final drums = _DrumMachine(
      tempo: preset.tempo,
      sampleRate: sampleRate,
      pattern: preset.drumPattern,
      kickVolume: preset.kickVolume,
      snareVolume: preset.snareVolume,
      hihatVolume: preset.hihatVolume,
    );

    // Initialize bass
    final bass = _BassLine(
      sampleRate: sampleRate,
      tempo: preset.tempo,
      rootNote: preset.rootNote,
      scale: preset.scale,
      pattern: preset.bassPattern,
    );

    // Initialize chord progression
    final chords = _ChordProgression(
      sampleRate: sampleRate,
      tempo: preset.tempo,
      rootNote: preset.rootNote,
      progression: preset.chordProgression,
      voicing: preset.chordVoicing,
    );

    // LFO for modulation
    double lfoPhase = 0;
    final lfoFreq = preset.lfoFreq;

    // Envelope
    final attackSamples = (preset.attackTime * sampleRate).round();
    final releaseSamples = (preset.releaseTime * sampleRate).round();

    for (var i = 0; i < numSamples; i++) {
      double sample = 0;
      final time = i / sampleRate;

      // LFO modulation
      final lfo = sin(2 * pi * lfoPhase);
      lfoPhase += lfoFreq / sampleRate;
      if (lfoPhase >= 1) lfoPhase -= 1;

      // Melody/pad from FM oscillators
      for (var j = 0; j < oscillators.length; j++) {
        final osc = oscillators[j];
        final modAmount = 1.0 + lfo * preset.lfoDepth;
        sample += osc.generate() * preset.voiceVolumes[j % preset.voiceVolumes.length] * modAmount;
      }

      // Drums
      if (preset.hasDrums) {
        sample += drums.generate();
      }

      // Bass
      if (preset.hasBass) {
        sample += bass.generate() * preset.bassVolume;
      }

      // Chords
      if (preset.hasChords) {
        sample += chords.generate() * preset.chordVolume;
      }

      // Apply envelope
      double envelope = 1.0;
      if (i < attackSamples) {
        envelope = i / attackSamples;
      } else if (i > numSamples - releaseSamples) {
        envelope = (numSamples - i) / releaseSamples;
      }

      // Master mix with proper gain staging
      sample *= envelope * preset.masterVolume * 0.3; // Reduce overall gain

      // Apply soft clipping to prevent harsh distortion
      sample = _softClip(sample);

      // Remove any DC offset
      sample *= 0.95;

      samples[i] = sample;
    }

    return samples;
  }

  /// Soft clipping using tanh for smooth saturation
  double _softClip(double x) {
    // Tanh provides smooth, warm saturation
    return x.isFinite ? (exp(2 * x) - 1) / (exp(2 * x) + 1) : 0.0;
  }

  /// Get preset for a genre
  _GenrePreset _getGenrePreset(String genre) {
    switch (genre.toLowerCase()) {
      case 'rock':
      case 'metal':
        return _GenrePreset.rock();
      case 'jazz':
      case 'blues':
        return _GenrePreset.jazz();
      case 'electronic':
      case 'techno':
      case 'house':
      case 'edm':
        return _GenrePreset.electronic();
      case 'ambient':
      case 'chill':
      case 'relaxing':
        return _GenrePreset.ambient();
      case 'classical':
      case 'orchestra':
        return _GenrePreset.classical();
      case 'lofi':
      case 'lo-fi':
        return _GenrePreset.lofi();
      default:
        return _GenrePreset.ambient(); // Default to ambient
    }
  }

  /// Create WAV file from float samples
  Uint8List _createWavFile(Float32List samples) {
    // Convert float to 16-bit PCM
    final pcmSamples = Int16List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      pcmSamples[i] = (samples[i] * 32767).round().clamp(-32768, 32767);
    }

    final dataSize = pcmSamples.length * 2;
    final fileSize = 36 + dataSize;

    final buffer = ByteData(44 + dataSize);
    var offset = 0;

    // RIFF header
    buffer.setUint8(offset++, 0x52); // 'R'
    buffer.setUint8(offset++, 0x49); // 'I'
    buffer.setUint8(offset++, 0x46); // 'F'
    buffer.setUint8(offset++, 0x46); // 'F'
    buffer.setUint32(offset, fileSize, Endian.little);
    offset += 4;
    buffer.setUint8(offset++, 0x57); // 'W'
    buffer.setUint8(offset++, 0x41); // 'A'
    buffer.setUint8(offset++, 0x56); // 'V'
    buffer.setUint8(offset++, 0x45); // 'E'

    // fmt chunk
    buffer.setUint8(offset++, 0x66); // 'f'
    buffer.setUint8(offset++, 0x6D); // 'm'
    buffer.setUint8(offset++, 0x74); // 't'
    buffer.setUint8(offset++, 0x20); // ' '
    buffer.setUint32(offset, 16, Endian.little); // Chunk size
    offset += 4;
    buffer.setUint16(offset, 1, Endian.little); // Audio format (PCM)
    offset += 2;
    buffer.setUint16(offset, 1, Endian.little); // Channels (mono)
    offset += 2;
    buffer.setUint32(offset, sampleRate, Endian.little);
    offset += 4;
    buffer.setUint32(offset, sampleRate * 2, Endian.little); // Byte rate
    offset += 4;
    buffer.setUint16(offset, 2, Endian.little); // Block align
    offset += 2;
    buffer.setUint16(offset, 16, Endian.little); // Bits per sample
    offset += 2;

    // data chunk
    buffer.setUint8(offset++, 0x64); // 'd'
    buffer.setUint8(offset++, 0x61); // 'a'
    buffer.setUint8(offset++, 0x74); // 't'
    buffer.setUint8(offset++, 0x61); // 'a'
    buffer.setUint32(offset, dataSize, Endian.little);
    offset += 4;

    // PCM data
    for (var i = 0; i < pcmSamples.length; i++) {
      buffer.setInt16(offset, pcmSamples[i], Endian.little);
      offset += 2;
    }

    return buffer.buffer.asUint8List();
  }
}

/// FM Oscillator
class _Oscillator {
  final double baseFreq;
  final double modRatio;
  final double modIndex;
  final int sampleRate;

  double _carrierPhase = 0;
  double _modPhase = 0;

  _Oscillator({
    required this.baseFreq,
    required this.modRatio,
    required this.modIndex,
    required this.sampleRate,
  });

  double generate() {
    // FM synthesis: carrier modulated by modulator
    final modFreq = baseFreq * modRatio;
    final modulator = sin(2 * pi * _modPhase) * modIndex;
    final carrier = sin(2 * pi * _carrierPhase + modulator);

    // Advance phases
    _carrierPhase += baseFreq / sampleRate;
    _modPhase += modFreq / sampleRate;

    if (_carrierPhase >= 1) _carrierPhase -= 1;
    if (_modPhase >= 1) _modPhase -= 1;

    return carrier;
  }
}

/// Simple drum machine
class _DrumMachine {
  final double tempo;
  final int sampleRate;
  final List<int> pattern; // 16-step pattern, bits: 1=kick, 2=snare, 4=hihat
  final double kickVolume;
  final double snareVolume;
  final double hihatVolume;

  int _stepIndex = 0;
  int _sampleCount = 0;
  int _samplesPerStep = 0;

  // Drum synth state
  double _kickPhase = 0;
  double _kickEnv = 0;
  double _snareEnv = 0;
  double _hihatEnv = 0;
  final _random = Random();

  _DrumMachine({
    required this.tempo,
    required this.sampleRate,
    required this.pattern,
    this.kickVolume = 0.5,
    this.snareVolume = 0.3,
    this.hihatVolume = 0.2,
  }) {
    // 16 steps per bar, 4 beats per bar
    _samplesPerStep = (sampleRate * 60 / tempo / 4).round();
  }

  double generate() {
    double sample = 0;

    // Check for step trigger
    if (_sampleCount >= _samplesPerStep) {
      _sampleCount = 0;
      _stepIndex = (_stepIndex + 1) % pattern.length;

      final step = pattern[_stepIndex];
      if (step & 1 != 0) _kickEnv = 1.0; // Kick
      if (step & 2 != 0) _snareEnv = 1.0; // Snare
      if (step & 4 != 0) _hihatEnv = 1.0; // Hihat
    }

    // Kick drum (pitched down sine with high-pass to reduce rumble)
    if (_kickEnv > 0.001) {
      final kickFreq = 80 + _kickEnv * 60; // Less extreme pitch bend
      final kickSample = sin(2 * pi * _kickPhase) * _kickEnv * kickVolume;
      sample += kickSample * 0.8; // Reduce kick volume slightly
      _kickPhase += kickFreq / sampleRate;
      _kickEnv *= 0.992; // Faster decay
    }

    // Snare (noise + tone)
    if (_snareEnv > 0.001) {
      final noise = _random.nextDouble() * 2 - 1;
      final tone = sin(2 * pi * 200 * _sampleCount / sampleRate);
      sample += (noise * 0.7 + tone * 0.3) * _snareEnv * snareVolume;
      _snareEnv *= 0.98;
    }

    // Hihat (filtered noise)
    if (_hihatEnv > 0.001) {
      final noise = _random.nextDouble() * 2 - 1;
      sample += noise * _hihatEnv * hihatVolume;
      _hihatEnv *= 0.9;
    }

    _sampleCount++;
    return sample;
  }
}

/// Simple bass line generator
class _BassLine {
  final int sampleRate;
  final double tempo;
  final int rootNote; // MIDI note number
  final List<int> scale; // Scale intervals
  final List<int> pattern; // Note pattern (scale degrees, -1 = rest)

  int _stepIndex = 0;
  int _sampleCount = 0;
  int _samplesPerStep = 0;
  double _phase = 0;
  double _currentFreq = 0;
  double _env = 0;

  _BassLine({
    required this.sampleRate,
    required this.tempo,
    required this.rootNote,
    required this.scale,
    required this.pattern,
  }) {
    _samplesPerStep = (sampleRate * 60 / tempo / 2).round(); // 8th notes
  }

  double generate() {
    // Check for step trigger
    if (_sampleCount >= _samplesPerStep) {
      _sampleCount = 0;
      _stepIndex = (_stepIndex + 1) % pattern.length;

      final noteIndex = pattern[_stepIndex];
      if (noteIndex >= 0) {
        final scaleNote = scale[noteIndex % scale.length];
        final octave = noteIndex ~/ scale.length;
        final midiNote = rootNote + scaleNote + octave * 12;
        _currentFreq = 440 * pow(2, (midiNote - 69) / 12).toDouble();
        _env = 1.0;
      }
    }

    double sample = 0;
    if (_env > 0.01) {
      // Simple saw wave for bass
      sample = (2 * _phase - 1) * _env;
      _phase += _currentFreq / sampleRate;
      if (_phase >= 1) _phase -= 1;
      _env *= 0.9995;
    }

    _sampleCount++;
    return sample;
  }
}

/// Chord progression generator
class _ChordProgression {
  final int sampleRate;
  final double tempo;
  final int rootNote;
  final List<List<int>> progression; // Chord intervals
  final List<int> voicing; // Octave offsets for each voice

  int _chordIndex = 0;
  int _sampleCount = 0;
  int _samplesPerChord = 0;
  final List<double> _phases = [];
  final List<double> _freqs = [];
  double _env = 0;

  _ChordProgression({
    required this.sampleRate,
    required this.tempo,
    required this.rootNote,
    required this.progression,
    required this.voicing,
  }) {
    // 1 chord per bar (4 beats)
    _samplesPerChord = (sampleRate * 60 / tempo * 4).round();
    for (var i = 0; i < 4; i++) {
      _phases.add(0);
      _freqs.add(0);
    }
    _triggerChord();
  }

  void _triggerChord() {
    final chord = progression[_chordIndex % progression.length];
    for (var i = 0; i < min(chord.length, 4); i++) {
      final octaveOffset = voicing.isNotEmpty ? voicing[i % voicing.length] : 0;
      final midiNote = rootNote + chord[i] + octaveOffset * 12;
      _freqs[i] = 440 * pow(2, (midiNote - 69) / 12).toDouble();
    }
    _env = 0.8;
  }

  double generate() {
    // Check for chord change
    if (_sampleCount >= _samplesPerChord) {
      _sampleCount = 0;
      _chordIndex++;
      _triggerChord();
    }

    double sample = 0;
    if (_env > 0.01) {
      for (var i = 0; i < _freqs.length; i++) {
        if (_freqs[i] > 0) {
          sample += sin(2 * pi * _phases[i]) * 0.15;
          _phases[i] += _freqs[i] / sampleRate;
          if (_phases[i] >= 1) _phases[i] -= 1;
        }
      }
      sample *= _env;
      _env *= 0.9999;
    }

    _sampleCount++;
    return sample;
  }
}

/// Genre preset configuration
class _GenrePreset {
  final int numVoices;
  final List<double> baseFrequencies;
  final List<double> modRatios;
  final double modIndex;
  final List<double> voiceVolumes;
  final double masterVolume;
  final double attackTime;
  final double releaseTime;
  final double lfoFreq;
  final double lfoDepth;
  final double tempo;
  final bool hasDrums;
  final bool hasBass;
  final bool hasChords;
  final List<int> drumPattern;
  final List<int> bassPattern;
  final List<List<int>> chordProgression;
  final List<int> chordVoicing;
  final int rootNote;
  final List<int> scale;
  final double kickVolume;
  final double snareVolume;
  final double hihatVolume;
  final double bassVolume;
  final double chordVolume;

  const _GenrePreset({
    required this.numVoices,
    required this.baseFrequencies,
    required this.modRatios,
    required this.modIndex,
    required this.voiceVolumes,
    required this.masterVolume,
    required this.attackTime,
    required this.releaseTime,
    required this.lfoFreq,
    required this.lfoDepth,
    required this.tempo,
    required this.hasDrums,
    required this.hasBass,
    required this.hasChords,
    required this.drumPattern,
    required this.bassPattern,
    required this.chordProgression,
    required this.chordVoicing,
    required this.rootNote,
    required this.scale,
    this.kickVolume = 0.5,
    this.snareVolume = 0.3,
    this.hihatVolume = 0.2,
    this.bassVolume = 0.4,
    this.chordVolume = 0.3,
  });

  /// Rock preset - energetic, driving beat
  factory _GenrePreset.rock() {
    return _GenrePreset(
      numVoices: 2,
      baseFrequencies: [220.0, 330.0],
      modRatios: [2.0, 3.0],
      modIndex: 3.0,
      voiceVolumes: [0.3, 0.2],
      masterVolume: 0.7,
      attackTime: 0.01,
      releaseTime: 0.5,
      lfoFreq: 0.1,
      lfoDepth: 0.1,
      tempo: 120,
      hasDrums: true,
      hasBass: true,
      hasChords: true,
      // Standard rock beat
      drumPattern: [1, 4, 2, 4, 1, 4, 2, 4, 1, 4, 2, 4, 1, 4, 2, 4],
      bassPattern: [0, -1, 0, -1, 0, -1, 2, -1],
      chordProgression: [
        [0, 4, 7],    // I
        [5, 9, 12],   // IV
        [0, 4, 7],    // I
        [7, 11, 14],  // V
      ],
      chordVoicing: [0, 0, 1],
      rootNote: 40, // E2
      scale: [0, 2, 4, 5, 7, 9, 11], // Major scale
      kickVolume: 0.6,
      snareVolume: 0.5,
      hihatVolume: 0.25,
      bassVolume: 0.5,
      chordVolume: 0.25,
    );
  }

  /// Jazz preset - smooth, complex harmonies
  factory _GenrePreset.jazz() {
    return _GenrePreset(
      numVoices: 3,
      baseFrequencies: [220.0, 277.0, 330.0],
      modRatios: [1.0, 1.5, 2.0],
      modIndex: 1.5,
      voiceVolumes: [0.25, 0.2, 0.15],
      masterVolume: 0.6,
      attackTime: 0.1,
      releaseTime: 1.0,
      lfoFreq: 0.3,
      lfoDepth: 0.15,
      tempo: 100,
      hasDrums: true,
      hasBass: true,
      hasChords: true,
      // Jazzy swing feel (simplified)
      drumPattern: [1, 0, 4, 0, 2, 0, 4, 0, 1, 0, 4, 0, 2, 0, 4, 4],
      bassPattern: [0, -1, 2, -1, 4, -1, 2, -1],
      chordProgression: [
        [0, 4, 7, 11],    // Maj7
        [5, 9, 12, 16],   // IV Maj7
        [2, 5, 9, 12],    // ii7
        [7, 11, 14, 17],  // V7
      ],
      chordVoicing: [0, 0, 1, 1],
      rootNote: 43, // G2
      scale: [0, 2, 4, 5, 7, 9, 11], // Major scale
      kickVolume: 0.3,
      snareVolume: 0.25,
      hihatVolume: 0.3,
      bassVolume: 0.4,
      chordVolume: 0.35,
    );
  }

  /// Electronic preset - synthesized, rhythmic
  factory _GenrePreset.electronic() {
    return _GenrePreset(
      numVoices: 2,
      baseFrequencies: [110.0, 440.0],
      modRatios: [4.0, 2.0],
      modIndex: 5.0,
      voiceVolumes: [0.2, 0.3],
      masterVolume: 0.7,
      attackTime: 0.005,
      releaseTime: 0.3,
      lfoFreq: 2.0,
      lfoDepth: 0.3,
      tempo: 128,
      hasDrums: true,
      hasBass: true,
      hasChords: true,
      // Four on the floor
      drumPattern: [1, 4, 2, 4, 1, 4, 2, 4, 1, 4, 2, 4, 1, 4, 2, 4],
      bassPattern: [0, 0, -1, 0, 0, 0, -1, 3],
      chordProgression: [
        [0, 3, 7],    // i (minor)
        [0, 3, 7],    // i
        [5, 8, 12],   // iv
        [7, 10, 14],  // v
      ],
      chordVoicing: [1, 1, 2],
      rootNote: 36, // C2
      scale: [0, 2, 3, 5, 7, 8, 10], // Minor scale
      kickVolume: 0.7,
      snareVolume: 0.4,
      hihatVolume: 0.3,
      bassVolume: 0.5,
      chordVolume: 0.2,
    );
  }

  /// Ambient preset - atmospheric, evolving
  factory _GenrePreset.ambient() {
    return _GenrePreset(
      numVoices: 4,
      baseFrequencies: [110.0, 165.0, 220.0, 330.0],
      modRatios: [1.0, 1.5, 2.0, 3.0],
      modIndex: 0.5,
      voiceVolumes: [0.2, 0.15, 0.15, 0.1],
      masterVolume: 0.5,
      attackTime: 2.0,
      releaseTime: 3.0,
      lfoFreq: 0.05,
      lfoDepth: 0.2,
      tempo: 60,
      hasDrums: false,
      hasBass: false,
      hasChords: true,
      drumPattern: [],
      bassPattern: [],
      chordProgression: [
        [0, 4, 7, 11],
        [0, 4, 7, 11],
        [5, 9, 12, 16],
        [2, 5, 9, 12],
      ],
      chordVoicing: [0, 1, 1, 2],
      rootNote: 48, // C3
      scale: [0, 2, 4, 5, 7, 9, 11],
      chordVolume: 0.5,
    );
  }

  /// Classical preset - orchestral, melodic
  factory _GenrePreset.classical() {
    return _GenrePreset(
      numVoices: 4,
      baseFrequencies: [220.0, 277.0, 330.0, 440.0],
      modRatios: [1.0, 2.0, 3.0, 4.0],
      modIndex: 1.0,
      voiceVolumes: [0.25, 0.2, 0.2, 0.15],
      masterVolume: 0.6,
      attackTime: 0.3,
      releaseTime: 1.5,
      lfoFreq: 0.2,
      lfoDepth: 0.1,
      tempo: 80,
      hasDrums: false,
      hasBass: true,
      hasChords: true,
      drumPattern: [],
      bassPattern: [0, -1, -1, -1, 4, -1, -1, -1],
      chordProgression: [
        [0, 4, 7],
        [5, 9, 12],
        [7, 11, 14],
        [0, 4, 7],
      ],
      chordVoicing: [0, 0, 1],
      rootNote: 48, // C3
      scale: [0, 2, 4, 5, 7, 9, 11],
      bassVolume: 0.3,
      chordVolume: 0.4,
    );
  }

  /// Lo-fi preset - relaxed, nostalgic
  factory _GenrePreset.lofi() {
    return _GenrePreset(
      numVoices: 3,
      baseFrequencies: [220.0, 277.0, 330.0],
      modRatios: [1.0, 2.0, 1.5],
      modIndex: 1.2,
      voiceVolumes: [0.2, 0.15, 0.15],
      masterVolume: 0.5,
      attackTime: 0.1,
      releaseTime: 0.8,
      lfoFreq: 0.1,
      lfoDepth: 0.15,
      tempo: 85,
      hasDrums: true,
      hasBass: true,
      hasChords: true,
      // Laid back beat
      drumPattern: [1, 0, 4, 0, 2, 0, 4, 0, 1, 0, 4, 0, 2, 0, 4, 4],
      bassPattern: [0, -1, 2, -1, 0, -1, 4, -1],
      chordProgression: [
        [0, 4, 7, 11],
        [5, 9, 12, 16],
        [2, 5, 9, 12],
        [7, 11, 14, 17],
      ],
      chordVoicing: [0, 0, 1, 1],
      rootNote: 45, // A2
      scale: [0, 2, 4, 5, 7, 9, 11],
      kickVolume: 0.35,
      snareVolume: 0.25,
      hihatVolume: 0.2,
      bassVolume: 0.35,
      chordVolume: 0.3,
    );
  }
}
