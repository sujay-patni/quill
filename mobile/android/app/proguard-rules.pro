# junrar (CBR comics): its logging facade looks for a binder that is not shipped; logging is unused.
-dontwarn org.slf4j.impl.StaticLoggerBinder
# Keep the RAR reader whole: it is small and only used for extraction.
-keep class com.github.junrar.** { *; }
