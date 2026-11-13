# Flutter/AdMob release builds: WorkManager initializes a Room database
# reflectively before the Flutter engine starts. AGP 9/R8 strict full mode may
# discard the generated no-argument constructor unless explicitly retained.
# https://github.com/googleads/googleads-mobile-flutter/issues/1444
-keep class * extends androidx.room.RoomDatabase { <init>(); }

# WorkManager also loads its InputMerger implementations reflectively.
-keep class * extends androidx.work.InputMerger { <init>(); }
