-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keepclassmembers class com.fatties.readtime.data.** { *; }

# Glance widgets are found by name from the manifest.
-keep class com.fatties.readtime.widget.** { *; }
# kotlinx.serialization keeps the generated serializers next to each model.
-keepclassmembers class com.fatties.readtime.data.** {
    *** Companion;
    kotlinx.serialization.KSerializer serializer(...);
}
