PC Diagnostics — Network Diagnostics V1
========================================

Files:
- main_network_v1.dart: replace lib/main.dart with this file's contents.
- main_network_v1.rs: replace diagnostic_core/src/main.rs with this file's contents.

What V1 checks:
- DNS resolution and TCP connection to port 443 for:
  - 1.1.1.1 (Cloudflare HTTPS endpoint)
  - www.google.com
  - www.speedtest.net
- Displays PASS / FAILED / PARTIAL, connection timing, diagnostic detail.
- Shows a VPN warning: VPN can increase ping and may reduce throughput, but can sometimes improve routing.

Important limitations:
- This version DOES NOT measure real download/upload throughput.
- The displayed milliseconds are TCP connection time, not ICMP ping.
- If Speedtest.net fails while other endpoints pass, the UI should be interpreted as endpoint unreachable, not proof that Internet is disconnected.
- No VPN detection is claimed in this version.
- No external crate dependencies were added.

Build from Git Bash at C:/src/pc_diagnostics:
  cd /c/src/pc_diagnostics/diagnostic_core
  cargo build
  cd /c/src/pc_diagnostics
  flutter analyze
  flutter run -d windows

For release:
  cd /c/src/pc_diagnostics/diagnostic_core
  cargo build --release
  cd /c/src/pc_diagnostics
  flutter build windows --release

Ensure the compiled diagnostic_core.exe is copied into the release app's diagnostic_core/ folder, as expected by the Flutter release search paths.
