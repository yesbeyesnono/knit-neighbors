# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# If your project uses WebView with JS, uncomment the following
# and specify the fully qualified class name to the JavaScript interface
# class:
#-keepclassmembers class fqcn.of.javascript.interface.for.webview {
#   public *;
#}

# Uncomment this to preserve the line number information for
# debugging stack traces.
#-keepattributes SourceFile,LineNumberTable

# If you keep the line number information, uncomment this to
# hide the original source file name.
#-renamesourcefileattribute SourceFile

# ===== knitup (2026-11-10, R8 켬) =====
# 웹(자바스크립트)이 Capacitor 플러그인을 '이름'으로 부른다 — R8 은 그 호출을 못 보므로 지우거나 이름을 바꾸면 안 된다.
# Capacitor 본체가 같은 규칙을 함께 배포하지만(consumerProguardFiles), 버전이 바뀌어도 안전하도록 여기에도 적어 둔다.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
-keep public class * extends com.getcapacitor.Plugin { *; }
-keep @com.getcapacitor.annotation.CapacitorPlugin public class * { *; }
-keepclassmembers class * { @com.getcapacitor.PluginMethod public <methods>; }
-keep class com.getcapacitor.** { *; }
# 우리 코드(MainActivity, Meta 이벤트 플러그인)
-keep class kr.co.firmtech.** { *; }
# 오류 보고서의 줄 번호는 남긴다(Play 가 mapping 파일로 원래 이름을 복원)
-keepattributes SourceFile, LineNumberTable
-renamesourcefileattribute SourceFile
