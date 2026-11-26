# =====================================================================
# Mercamigo · Reglas de R8 (ProGuard) para la compilacion release
#
# Flutter activa R8 en las compilaciones release y anade este fichero
# automaticamente (ver FlutterPlugin.kt: releaseBuildType.proguardFiles).
#
# ---------------------------------------------------------------------
# POR QUE ESTAS REGLAS SON NECESARIAS
#
# 1) ML Kit (lector de codigos de barras y QR)
#
# El plugin `mobile_scanner` declara en sus propias reglas:
#
#     -keep class com.google.mlkit.* { *; }
#
# Con UNA sola estrella, `com.google.mlkit.*` solo cubre las clases
# directamente del paquete `com.google.mlkit`: **no** cubre los
# subpaquetes, como `com.google.mlkit.vision.barcode.internal`.
#
# Con R8 activado (por defecto en release) las clases internas del lector
# de codigos de barras se renombran o se eliminan, el objeto del escaner
# queda nulo y la camara no arranca. El error real que se ve en el
# dispositivo es:
#
#   java.lang.NullPointerException: Attempt to invoke virtual method
#   'com.google.mlkit.vision.barcode.internal.zzg.a(...)' on a null object reference
#
# 2) Kotlin
#
# En modo "full", R8 reescribe las firmas de los metodos `suspend` y deja
# llamadas que ya no existen.
#
# 3) Plugins de Flutter con interfaces generadas por Pigeon
#
# R8 elimina la interfaz `SharedPreferencesApi` (y sus metodos) del APK y
# la llamada se queda sin metodo. La app ni siquiera arranca:
#
#   java.lang.NoSuchMethodError: no non-static method
#   "Lio/flutter/plugins/sharedpreferences/SharedPreferencesApiRegistrar;.getAll(...)"
# ---------------------------------------------------------------------

# ML Kit (lector de codigos de barras y QR).
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google.android.libraries.barhopper.** { *; }
-keep class com.google.photos.** { *; }
-dontwarn com.google.mlkit.**

# Kotlin: metodos `suspend`, resultados y marcadores de construccion.
#
# OJO: `kotlin.Result` tiene clases anidadas (`kotlin.Result$Failure` y
# `kotlin.Result$Success`). Si se conserva solo la clase madre, R8 elimina
# las anidadas y el arranque falla con:
#   java.lang.ClassNotFoundException: Didn't find class "kotlin/Result$Failure"
# Por eso se conservan con `**` (la clase y sus anidadas).
-keep class kotlin.coroutines.** { *; }
-keep class kotlin.Result** { *; }
-keep class kotlin.Unit { *; }
-keep class kotlin.enums.** { *; }
-keep class kotlin.jvm.internal.DefaultConstructorMarker { *; }
-keepclassmembers enum kotlin.enums.EnumEntries {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Plugins de Flutter: las interfaces que genera Pigeon no se pueden
# eliminar ni reescribir (los llama el canal de plataforma).
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep interface io.flutter.plugins.sharedpreferences.** { *; }
-keep class io.flutter.plugins.pathprovider.** { *; }
-keep interface io.flutter.plugins.pathprovider.** { *; }

# Los enumerados de ML Kit y del plugin (values() / valueOf()).
-keepclassmembers class * extends java.lang.Enum {
    <fields>;
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
