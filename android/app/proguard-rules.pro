# Flutter Gemma & MediaPipe R8 Keep Rules
# Prevents R8 from removing classes needed by flutter_gemma and MediaPipe

# Keep MediaPipe proto classes
-keep class com.google.mediapipe.proto.** { *; }
-keep interface com.google.mediapipe.proto.** { *; }

# Keep MediaPipe framework classes
-keep class com.google.mediapipe.framework.** { *; }
-keep interface com.google.mediapipe.framework.** { *; }

# Keep MediaPipe solutions classes
-keep class com.google.mediapipe.solutions.** { *; }
-keep interface com.google.mediapipe.solutions.** { *; }

# Keep TensorFlow Lite classes
-keep class org.tensorflow.lite.** { *; }
-keep interface org.tensorflow.lite.** { *; }

# Keep flutter_gemma native classes
-keep class com.google.ai.** { *; }
-keep interface com.google.ai.** { *; }

# Keep Protobuf runtime classes
-keep class com.google.protobuf.** { *; }
-keep interface com.google.protobuf.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep enums
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep R8 from removing used inner classes
-keepclassmembers class * {
    *** lambda*(...);
}

# Prevent R8 from stripping out inner classes
-keep class **.R$* {
    <fields>;
}

# Keep BuildConfig
-keep class **.BuildConfig {
    public static <fields>;
}

# General keep rules for better compatibility
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# Suppress warnings for missing MediaPipe proto classes that only exist in native libraries
-dontwarn com.google.mediapipe.proto.CalculatorProfileProto$CalculatorProfile
-dontwarn com.google.mediapipe.proto.GraphTemplateProto$CalculatorGraphTemplate
-dontwarn com.google.mediapipe.proto.**
