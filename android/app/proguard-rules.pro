# ============================================================
# ProGuard / R8 rules — TermulLog
# ============================================================

# Flutter embedding
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.embedding.engine.** { *; }

# HTTP & Network
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-keep class com.android.okhttp.** { *; }
-keep class org.chromium.net.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# FIX: namespace yang benar (com.termullog.app, bukan com.example.termullog)
-keep class com.termullog.app.** { *; }

# Kotlin metadata & coroutines
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-keepclassmembers class **$WhenMappings { <fields>; }
-keepclassmembers class kotlin.Metadata { public <methods>; }

# Annotations & signatures (dibutuhkan Gson, Retrofit, dll)
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keepattributes Exceptions

# JavaScript interface
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Serializable
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    !static !transient <fields>;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# FIX: hapus rule `-keepclassmembers class * { *** *; }` yang terlalu luas
# dan menonaktifkan seluruh obfuscation. Class model spesifik cukup di-keep
# via annotation atau rule yang lebih sempit di bawah ini.

# Geolocator
-keep class com.baseflow.geolocator.** { *; }

# Camera
-keep class io.flutter.plugins.camera.** { *; }

# Gallery saver
-keep class com.sharath07.gallery_saver.** { *; }

# Play Core (tidak digunakan — suppress warning R8)
-dontwarn com.google.android.play.core.**
