# Flutter giriş noktaları ve eklenti kayıtları çalışma zamanında yansıma ile
# bulunabilir. Uygulamanın kendi Kotlin sınıfları yine R8 tarafından küçültülür.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class androidx.lifecycle.** { *; }

# Media3/ExoPlayer sınıflarının servis ve codec adları bazı Fire OS sürümlerinde
# yansıma ile okunur. Oynatma davranışını korumak için yalnız bu yüzeyi tut.
-keep class androidx.media3.** { *; }
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn org.checkerframework.**
-dontwarn javax.annotation.**

# TIVUQIPTV deferred Flutter components kullanmaz. Flutter motorundaki Google
# Play dynamic-feature köprüsü Amazon APK'sında erişilemez ve güvenle atılır.
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Flutter MethodChannel üzerinden çağrılan yerel köprü sınıflarını koru.
-keep class com.tivuq.iptv.MainActivity { *; }
-keep class com.tivuq.iptv.DeviceIdentityPlugin { *; }
-keep class com.tivuq.iptv.Media3PlayerPlugin { *; }
-keep class com.tivuq.iptv.Media3PlayerView { *; }
-keep class com.tivuq.iptv.Exo2PlayerPlugin { *; }
-keep class com.tivuq.iptv.NativeLiveTvPlugin { *; }
-keep class com.tivuq.iptv.AutoLaunchService { *; }
-keep class com.tivuq.iptv.BootCompletedReceiver { *; }
