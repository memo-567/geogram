/// FFI implementations for native platforms (Linux, macOS, Windows, etc.)
/// This file re-exports the actual FFI implementations.

export 'alsa_recorder.dart' show AlsaRecorder;
export 'alsa_player.dart' show AlsaPlayer, AlsaPlayerState;
export 'opus_encoder.dart' show OpusEncoder, OPUS_APPLICATION_VOIP;
export 'opus_decoder.dart' show OpusDecoder;

// Re-export OggOpusReader from ogg_opus_writer.dart
export 'ogg_opus_writer.dart' show OggOpusReader;
