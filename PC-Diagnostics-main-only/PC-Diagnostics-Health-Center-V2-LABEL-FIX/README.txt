PC Diagnostics — Health Center V2 / Repair Engine

REPLACE:
  main.dart -> C:\src\pc_diagnostics\lib\main.dart
  main.rs   -> C:\src\pc_diagnostics\diagnostic_core\src\main.rs

BUILD in Git Bash:
  cd /c/src/pc_diagnostics/diagnostic_core
  cargo build
  cd /c/src/pc_diagnostics
  dart format lib/main.dart
  flutter analyze
  flutter run -d windows

For Release:
  cd diagnostic_core && cargo build --release
  cd .. && flutter build windows --release
  Copy diagnostic_core/target/release/diagnostic_core.exe next to the Flutter Release EXE.

V2:
- Preserves original JSON scan when no CLI args are supplied.
- New strict Rust CLI: --integrity scan-sfc|scan-dism|repair-sfc|repair-dism.
- SFC /verifyonly, DISM /ScanHealth, SFC /scannow, DISM /RestoreHealth.
- Each action has a confirmation dialog and requires the app to be launched as Administrator.
- The app does NOT elevate automatically, and does NOT repair on ordinary scans.
- Results shown in Flutter and written to LOCALAPPDATA/PCDiagnostics/repair_logs.
- Windows output may be localized. Review full output and exit code; never treat exit code alone as proof of complete health.
- SFC/DISM can take a long time; DISM may need internet or a repair source.
- No Flutter/Rust toolchains were available here; NOT verified by actual compilation.

SAFETY:
Back up important data, save open work, and run repairs only if appropriate.
No arbitrary command input. The tool does not auto-delete data, edit Registry, or disable services.
