PC Diagnostics Health & Trust Center V1

Replace lib/main.dart with main.dart. Rust main.rs is unchanged; existing Network V1 backend is preserved.

This phase adds a read-only Health & Trust Center with CPU WMI/CPUID consistency, disk free space, RAM reporting and BIOS/model availability. PASS means only the listed check passed, NOT that hardware is proven healthy. No repair commands execute in V1.

Run: dart format lib/main.dart; flutter analyze; flutter run -d windows

No Flutter or Cargo toolchain is installed in the packaging environment, so compile/build is not verified.
