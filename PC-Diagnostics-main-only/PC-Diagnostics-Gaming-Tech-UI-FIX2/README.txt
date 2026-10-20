PC Diagnostics — Gaming / Tech UI (compatibility patch)

Replace lib/main.dart with main.dart from this package.
Keep your existing diagnostic_core/src/main.rs Network V1 if it already works.

Compatibility adjustment: removed ThemeData.cardTheme: CardThemeData because that type differs across Flutter SDK versions. Individual UI surfaces still have their own dark-blue styling.

Validate from Git Bash:
  cd /c/src/pc_diagnostics
  dart format lib/main.dart
  flutter analyze
  flutter run -d windows

This source has not been compiled in this environment; if the build still fails, paste the FIRST error from `flutter analyze` or the terminal output above `Error: Build Process Failed`.
