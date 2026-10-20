import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const PcDiagnosticsApp());
}

class PcDiagnosticsApp extends StatelessWidget {
  const PcDiagnosticsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PC Diagnostics',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const DiagnosticsHome(),
    );
  }
}

class DiagnosticsHome extends StatefulWidget {
  const DiagnosticsHome({super.key});

  @override
  State<DiagnosticsHome> createState() => _DiagnosticsHomeState();
}

class _DiagnosticsHomeState extends State<DiagnosticsHome> {
  bool _running = false;
  String _message = 'Ready to scan hardware and network connectivity.';
  Map<String, dynamic>? _data;

  Future<void> _runDiagnostic() async {
    if (_running) return;

    if (!Platform.isWindows) {
      setState(() {
        _message =
            'This diagnostic backend currently supports Windows only.';
      });
      return;
    }

    setState(() {
      _running = true;
      _message = 'Collecting hardware information...';
    });

    try {
      final appDirectory =
          File(Platform.resolvedExecutable).parent;

      // ============================================================
      // RUST CORE SEARCH PARAMETERS
      // ============================================================
      //
      // The app searches for diagnostic_core.exe instead of using
      // a hard-coded development path.
      //
      // This allows portable Beta releases to run from any folder.
      // ============================================================

      final rustExecutable = Platform.isWindows
          ? 'diagnostic_core.exe'
          : 'diagnostic_core';

      final List<String> possiblePaths;

      if (kReleaseMode) {
        possiblePaths = [
          // 1. Rust core next to the Flutter executable.
          '${appDirectory.path}'
              '${Platform.pathSeparator}$rustExecutable',

          // 2. Rust core inside diagnostic_core/.
          '${appDirectory.path}'
              '${Platform.pathSeparator}diagnostic_core'
              '${Platform.pathSeparator}$rustExecutable',

          // 3. Rust core inside core/.
          '${appDirectory.path}'
              '${Platform.pathSeparator}core'
              '${Platform.pathSeparator}$rustExecutable',
        ];
      } else {
        possiblePaths = [
          // Development build.
          '${Directory.current.path}'
              '${Platform.pathSeparator}diagnostic_core'
              '${Platform.pathSeparator}target'
              '${Platform.pathSeparator}debug'
              '${Platform.pathSeparator}$rustExecutable',

          // Fallback for development/build directories.
          '${appDirectory.path}'
              '${Platform.pathSeparator}$rustExecutable',
        ];
      }

      File? executable;

      for (final path in possiblePaths) {
        final candidate = File(path);

        if (await candidate.exists()) {
          executable = candidate;
          break;
        }
      }

      if (executable == null) {
        throw Exception(
          'Rust diagnostic core not found.\n\n'
          'Expected: $rustExecutable\n\n'
          'Searched locations:\n'
          '${possiblePaths.join('\n')}',
        );
      }

      final result = await Process.run(
        executable.path,
        [],
      );

      if (result.exitCode != 0) {
        throw Exception(
          result.stderr.toString().trim().isNotEmpty
              ? result.stderr.toString()
              : 'Diagnostic core exited with code '
                  '${result.exitCode}.',
        );
      }

      final decoded = jsonDecode(
        result.stdout.toString(),
      );

      if (decoded is! Map<String, dynamic>) {
        throw const FormatException(
          'Invalid diagnostic JSON.',
        );
      }

      setState(() {
        _data = decoded;
        _message =
            'Hardware and basic network checks completed.';
      });
    } catch (error) {
      setState(() {
        _message = 'Scan failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
        });
      }
    }
  }

  String _status(String key) {
    if (_running) return 'SCANNING';
    if (_data == null) return 'READY';

    switch (key) {
      case 'cpu':
        return _data!['cpu'] != null
            ? 'READ'
            : 'UNAVAILABLE';

      case 'memory':
        return _data!['memory'] != null
            ? 'READ'
            : 'UNAVAILABLE';

      case 'storage':
        return (_data!['storage'] as List?)?.isNotEmpty == true
            ? 'READ'
            : 'UNAVAILABLE';

      case 'gpu':
        return (_data!['gpu'] as List?)?.isNotEmpty == true
            ? 'READ'
            : 'UNAVAILABLE';

      case 'battery':
        return _data!['battery']?['detected'] == true
            ? 'DETECTED'
            : 'UNAVAILABLE';

      case 'network':
        final network = _data!['network'];
        return network != null
            ? (network['overall_status'] ?? 'PARTIAL').toString()
            : 'UNAVAILABLE';

      case 'system':
        return (_data!['computer'] != null ||
                _data!['bios'] != null)
            ? 'READ'
            : 'UNAVAILABLE';

      case 'thermals':
        return 'UNAVAILABLE';

      default:
        return 'READY';
    }
  }

  String _detail(String key) {
    if (_data == null) {
      return key == 'thermals'
          ? 'Temperature sensor not connected'
          : 'Run diagnostic to inspect';
    }

    switch (key) {
      case 'cpu':
        final cpu = _data!['cpu'];

        if (cpu == null) {
          return 'No CPU data';
        }

        final verification =
            cpu['verification_status'] ?? 'UNVERIFIED';

        final cpuidName = cpu['cpuid_name'];

        return '${cpu['name']} • '
            '${cpu['core_count']} cores • '
            '${cpu['frequency_mhz']} MHz\n'
            'CPUID: ${cpuidName ?? 'Unavailable'}\n'
            'Verification: $verification';

      case 'memory':
        final memory = _data!['memory'];

        if (memory == null) {
          return 'No memory data';
        }

        return '${memory['used_mb']} MB used / '
            '${memory['total_mb']} MB total';

      case 'storage':
        final disks = _data!['storage'] as List? ?? [];

        if (disks.isEmpty) {
          return 'No storage data';
        }

        return disks
            .map(
              (disk) =>
                  '${disk['mount_point']} '
                  '${disk['available_gb']} GB free',
            )
            .join(' • ');

      case 'gpu':
        final gpus = _data!['gpu'] as List? ?? [];

        if (gpus.isEmpty) {
          return 'No GPU detected';
        }

        return gpus.map((gpu) {
          final vram = gpu['vram_mb'];

          return '${gpu['name']}'
              '${vram == null ? '' : ' • $vram MB reported VRAM'}';
        }).join('\n');

      case 'battery':
        final battery = _data!['battery'];

        if (battery == null ||
            battery['detected'] != true) {
          return 'No battery detected';
        }

        final charge = battery['charge_percent'];
        final runtime = battery['estimated_runtime_minutes'];

        // Ignore clearly invalid WMI runtime values.
        final validRuntime = runtime is int &&
            runtime >= 0 &&
            runtime <= 10080;

        return '${charge == null ? 'Charge unknown' : '$charge% charge'}'
            '${validRuntime ? ' • '
                '${runtime ~/ 60}h ${runtime % 60}m estimated' : ''}';

      case 'network':
        final network = _data!['network'];
        if (network == null) return 'Network diagnostics not available';
        final checks = network['checks'] as List? ?? [];
        final lines = <String>[];
        for (final raw in checks) {
          if (raw is! Map) continue;
          final status = raw['status'] ?? 'UNKNOWN';
          final latency = raw['latency_ms'];
          lines.add('${raw['name']}: $status'
              '${latency == null ? '' : ' • ${latency} ms'}\n'
              '${raw['detail'] ?? ''}');
        }
        lines.add('');
        lines.add('VPN WARNING: ${network['vpn_warning'] ?? ''}');
        lines.add('');
        lines.add('${network['note'] ?? ''}');
        return lines.join('\n');

      case 'system':
        final computer = _data!['computer'];
        final bios = _data!['bios'];

        if (computer == null && bios == null) {
          return 'No system information';
        }

        final manufacturer =
            computer?['manufacturer'] ??
                'Unknown manufacturer';

        final model =
            computer?['model'] ??
                'Unknown model';

        final biosManufacturer =
            bios?['manufacturer'] ??
                'Unknown BIOS vendor';

        final biosVersion =
            bios?['version'] ??
                'Unknown';

        String biosDate =
            bios?['release_date'] ?? '';

        // WMI BIOS date format:
        // YYYYMMDDHHMMSS.mmmmmmsUUU
        if (biosDate.length >= 8) {
          final rawDate =
              biosDate.substring(0, 8);

          if (RegExp(r'^\d{8}$')
              .hasMatch(rawDate)) {
            biosDate =
                '${rawDate.substring(6, 8)}/'
                '${rawDate.substring(4, 6)}/'
                '${rawDate.substring(0, 4)}';
          }
        }

        return '$manufacturer $model\n'
            'BIOS: $biosManufacturer '
            '$biosVersion'
            '${biosDate.isEmpty ? '' : ' • $biosDate'}';

      case 'thermals':
        return 'Temperature readings are not implemented yet';

      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = [
      (Icons.memory, 'CPU', 'cpu'),
      (Icons.memory, 'Memory', 'memory'),
      (Icons.storage, 'Storage', 'storage'),
      (Icons.videogame_asset, 'GPU', 'gpu'),
      (Icons.thermostat, 'Thermals', 'thermals'),
      (Icons.battery_full, 'Battery', 'battery'),
      (Icons.computer, 'System', 'system'),
      (Icons.language, 'Network', 'network'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'PC Diagnostics',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'System Overview',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Hardware diagnostic center',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 15,
              ),
            ),

            const SizedBox(height: 16),

            Text(_message),

            const SizedBox(height: 16),

            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 2.0,
                children: cards.map((item) {
                  return DiagnosticCard(
                    icon: item.$1,
                    name: item.$2,
                    status: _status(item.$3),
                    detail: _detail(item.$3),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: FilledButton.icon(
                onPressed:
                    _running ? null : _runDiagnostic,
                icon: _running
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(
                  _running
                      ? 'SCANNING HARDWARE...'
                      : 'RUN FULL DIAGNOSTIC',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DiagnosticCard extends StatelessWidget {
  final IconData icon;
  final String name;
  final String status;
  final String detail;

  const DiagnosticCard({
    super.key,
    required this.icon,
    required this.name,
    required this.status,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor =
        status == 'UNAVAILABLE'
            ? Colors.orange
            : status == 'SCANNING'
                ? Colors.lightBlueAccent
                : status == 'READY'
                    ? Colors.grey
                    : Colors.greenAccent;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 26,
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  detail,
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}