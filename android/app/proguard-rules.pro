# Suppress warnings for Play Core classes (not included in F-Droid builds)
-dontwarn com.google.android.play.core.**

# TensorFlow Lite rules
-keep class org.tensorflow.** { *; }
-keep interface org.tensorflow.** { *; }
-dontwarn org.tensorflow.**
-dontwarn org.tensorflow.lite.gpu.GpuDelegateFactory$Options

# ONNX Runtime rules
-keep class ai.onnxruntime.** { *; }

# Keep TFLite Flutter plugin
-keep class com.tfliteflutter.** { *; }
-dontwarn com.tfliteflutter.**
