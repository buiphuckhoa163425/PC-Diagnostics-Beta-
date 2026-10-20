import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

void main() => runApp(const PcDiagnosticsApp());

const _bg = Color(0xFF070B14);
const _panel = Color(0xFF101827);
const _panel2 = Color(0xFF141F32);
const _blue = Color(0xFF38BDF8);
const _cyan = Color(0xFF67E8F9);

class PcDiagnosticsApp extends StatelessWidget {
  const PcDiagnosticsApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'PC Diagnostics',
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _bg,
          colorScheme: ColorScheme.fromSeed(
            seedColor: _blue,
            brightness: Brightness.dark,
            surface: _panel,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: _bg,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
          ),
        ),
        home: const DiagnosticsHome(),
      );
}

class _Section {
  final String id;
  final IconData icon;
  final String en;
  final String vi;
  final String subtitleEn;
  final String subtitleVi;
  const _Section(this.id, this.icon, this.en, this.vi, this.subtitleEn,
      this.subtitleVi);
}

const _sections = <_Section>[
  _Section('overview', Icons.dashboard_rounded, 'Overview', 'Tổng quan',
      'System health at a glance', 'Tình trạng hệ thống tổng quan'),
  _Section('health', Icons.health_and_safety_rounded, 'Health & Trust Center', 'Sức khỏe & Độ tin cậy',
      'Hardware checks and recommendations', 'Kiểm tra phần cứng và khuyến nghị'),
  _Section('cpu', Icons.memory_rounded, 'Processor', 'Bộ xử lý CPU',
      'Processor identity and verification', 'Tên CPU và xác minh thông tin'),
  _Section('memory', Icons.storage_rounded, 'Memory', 'Bộ nhớ RAM',
      'Installed and currently used memory', 'Dung lượng RAM và mức sử dụng'),
  _Section('storage', Icons.sd_storage_rounded, 'Storage', 'Ổ lưu trữ',
      'Volumes and available capacity', 'Phân vùng và dung lượng còn trống'),
  _Section('gpu', Icons.videogame_asset_rounded, 'Graphics', 'Đồ họa GPU',
      'Graphics adapters and reported VRAM', 'Card đồ họa và VRAM được báo cáo'),
  _Section('thermals', Icons.device_thermostat_rounded, 'Thermals', 'Nhiệt độ',
      'Temperature sensor availability', 'Khả năng đọc cảm biến nhiệt độ'),
  _Section('battery', Icons.battery_charging_full_rounded, 'Battery', 'Pin',
      'Charge and estimated runtime', 'Mức pin và thời lượng ước tính'),
  _Section('system', Icons.computer_rounded, 'System / BIOS', 'Hệ thống / BIOS',
      'Device identity and firmware details', 'Thông tin máy và firmware'),
  _Section('network', Icons.language_rounded, 'Network', 'Mạng Internet',
      'DNS and HTTPS endpoint connectivity', 'Kiểm tra DNS và kết nối HTTPS'),
];

class DiagnosticsHome extends StatefulWidget {
  const DiagnosticsHome({super.key});
  @override
  State<DiagnosticsHome> createState() => _DiagnosticsHomeState();
}

class _DiagnosticsHomeState extends State<DiagnosticsHome> {
  bool _running = false;
  bool _vietnamese = true;
  String _selected = 'overview';
  String _message = 'Sẵn sàng kiểm tra phần cứng và kết nối mạng.';
  String? _error;
  Map<String, dynamic>? _data;
  bool _repairBusy = false;
  String? _repairOutput;
  String? _repairLogPath;
  String? _repairAction;


  String t(String en, String vi) => _vietnamese ? vi : en;
  _Section get selectedSection =>
      _sections.firstWhere((s) => s.id == _selected);

  Future<File> _findCore() async {
    final appDirectory = File(Platform.resolvedExecutable).parent;
    const name = 'diagnostic_core.exe';
    final paths = kReleaseMode
        ? <String>[
            '${appDirectory.path}${Platform.pathSeparator}$name',
            '${appDirectory.path}${Platform.pathSeparator}diagnostic_core${Platform.pathSeparator}$name',
            '${appDirectory.path}${Platform.pathSeparator}core${Platform.pathSeparator}$name',
          ]
        : <String>[
            '${Directory.current.path}${Platform.pathSeparator}diagnostic_core${Platform.pathSeparator}target${Platform.pathSeparator}debug${Platform.pathSeparator}$name',
            '${appDirectory.path}${Platform.pathSeparator}$name',
          ];
    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) return file;
    }
    throw Exception('diagnostic_core.exe not found: ${paths.join(', ')}');
  }

  Future<void> _runIntegrity(String action, String label, bool repair) async {
    if (_repairBusy || _running || !Platform.isWindows) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(repair ? t('Confirm Windows repair', 'Xác nhận sửa Windows')
                           : t('Confirm integrity check', 'Xác nhận kiểm tra hệ thống')),
        content: Text(t(
          '$label. Requires Administrator. This can take a long time. '
          '${repair ? 'System files may be modified; save your work first.' : 'This check does not request repairs.'} '
          'The app will not automatically elevate privileges.',
          '$label. Yêu cầu quyền Administrator và có thể mất nhiều thời gian. '
          '${repair ? 'Tệp hệ thống có thể bị thay đổi; hãy lưu công việc trước.' : 'Bước này chỉ kiểm tra, không yêu cầu sửa.'} '
          'Ứng dụng không tự động nâng quyền.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(t('Cancel', 'Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(t('Continue', 'Tiếp tục'))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _repairBusy = true; _repairAction = label; _repairOutput = null; _repairLogPath = null; });
    try {
      final core = await _findCore();
      // Windows tools may take several minutes; Process.run waits without blocking Flutter UI.
      final result = await Process.run(core.path, ['--integrity', action],
          stdoutEncoding: systemEncoding, stderrEncoding: systemEncoding);
      if (result.exitCode != 0) {
        throw Exception('Core exit ${result.exitCode}: ${result.stderr}');
      }
      final payload = jsonDecode(result.stdout.toString());
      if (payload is! Map) throw const FormatException('Invalid integrity result');
      final ok = payload['ok'] == true;
      final output = [
        'Action: $action', 'Status: ${ok ? 'COMPLETED (review output)' : 'FAILED / NEEDS ATTENTION'}',
        if (payload['exit_code'] != null) 'Exit code: ${payload['exit_code']}',
        if (payload['error'] != null) 'Error: ${payload['error']}',
        if (payload['stdout'] != null) '${payload['stdout']}',
        if (payload['stderr'] != null && payload['stderr'].toString().isNotEmpty) '${payload['stderr']}',
        if (payload['note'] != null) '${payload['note']}',
      ].join('\n\n');
      String? logPath;
      try {
        final dir = Directory('${Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path}${Platform.pathSeparator}PCDiagnostics${Platform.pathSeparator}repair_logs');
        await dir.create(recursive: true);
        final now = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
        final log = File('${dir.path}${Platform.pathSeparator}$now-$action.txt');
        await log.writeAsString(output, flush: true);
        logPath = log.path;
      } catch (e) {
        logPath = t('Could not save log: $e', 'Không thể lưu nhật ký: $e');
      }
      if (mounted) setState(() { _repairOutput = output; _repairLogPath = logPath; });
    } catch (e) {
      if (mounted) setState(() => _repairOutput = 'ERROR: $e');
    } finally {
      if (mounted) setState(() => _repairBusy = false);
    }
  }

  Widget _repairCenter() => _panelCard(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(t('WINDOWS REPAIR CENTER', 'TRUNG TÂM SỬA LỖI WINDOWS'),
          style: const TextStyle(color: _cyan, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text(t('All actions require confirmation and Administrator privileges. Scan first, then decide whether repair is needed.',
          'Mọi thao tác đều yêu cầu xác nhận và quyền Administrator. Hãy kiểm tra trước, sau đó mới quyết định sửa.'),
          style: const TextStyle(color: Color(0xFFB7C5D8), height: 1.5)),
      const SizedBox(height: 16),
      Wrap(spacing: 10, runSpacing: 10, children: [
        OutlinedButton.icon(onPressed: _repairBusy || _running ? null : () => _runIntegrity('scan-sfc', 'SFC /verifyonly', false),
          icon: const Icon(Icons.search), label: const Text('SFC Verify')),
        OutlinedButton.icon(onPressed: _repairBusy || _running ? null : () => _runIntegrity('scan-dism', 'DISM /ScanHealth', false),
          icon: const Icon(Icons.search), label: const Text('DISM ScanHealth')),
        FilledButton.icon(onPressed: _repairBusy || _running ? null : () => _runIntegrity('repair-sfc', 'SFC /scannow', true),
          icon: const Icon(Icons.build_outlined), label: const Text('SFC Repair')),
        FilledButton.icon(onPressed: _repairBusy || _running ? null : () => _runIntegrity('repair-dism', 'DISM /RestoreHealth', true),
          icon: const Icon(Icons.build_outlined), label: const Text('DISM RestoreHealth')),
      ]),
      if (_repairBusy) ...[
        const SizedBox(height: 16),
        const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Text('${_repairAction ?? ''} — ${t('Working… please wait', 'Đang xử lý… vui lòng đợi')}'),
      ],
      if (_repairOutput != null) ...[
        const SizedBox(height: 16),
        Text(t('LATEST RESULT', 'KẾT QUẢ GẦN NHẤT'), style: const TextStyle(color: _cyan, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SelectableText(_repairOutput!, style: const TextStyle(fontSize: 12, height: 1.5)),
        if (_repairLogPath != null) ...[const SizedBox(height: 8), SelectableText('${t('Log', 'Nhật ký')}: $_repairLogPath')],
        const SizedBox(height: 8),
        TextButton.icon(onPressed: _repairBusy || _running ? null : _runDiagnostic,
          icon: const Icon(Icons.refresh), label: Text(t('Re-scan hardware', 'Quét lại phần cứng'))),
      ],
    ],
  ));

  Future<void> _runDiagnostic() async {
    if (_running || _repairBusy) return;
    if (!Platform.isWindows) {
      setState(() => _message = t(
          'This diagnostic backend currently supports Windows only.',
          'Bộ chẩn đoán hiện chỉ hỗ trợ Windows.'));
      return;
    }
    setState(() {
      _running = true;
      _error = null;
      _message = t('Collecting hardware and network information…',
          'Đang thu thập thông tin phần cứng và mạng…');
    });
    try {
      final appDirectory = File(Platform.resolvedExecutable).parent;
      const rustExecutable = 'diagnostic_core.exe';
      final List<String> possiblePaths;
      if (kReleaseMode) {
        possiblePaths = [
          '${appDirectory.path}${Platform.pathSeparator}$rustExecutable',
          '${appDirectory.path}${Platform.pathSeparator}diagnostic_core${Platform.pathSeparator}$rustExecutable',
          '${appDirectory.path}${Platform.pathSeparator}core${Platform.pathSeparator}$rustExecutable',
        ];
      } else {
        possiblePaths = [
          '${Directory.current.path}${Platform.pathSeparator}diagnostic_core${Platform.pathSeparator}target${Platform.pathSeparator}debug${Platform.pathSeparator}$rustExecutable',
          '${appDirectory.path}${Platform.pathSeparator}$rustExecutable',
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
        throw Exception('Rust diagnostic core not found.\n\n'
            'Expected: $rustExecutable\n\nSearched locations:\n${possiblePaths.join('\n')}');
      }
      final result = await Process.run(executable.path, []);
      if (result.exitCode != 0) {
        throw Exception(result.stderr.toString().trim().isNotEmpty
            ? result.stderr.toString()
            : 'Diagnostic core exited with code ${result.exitCode}.');
      }
      final decoded = jsonDecode(result.stdout.toString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid diagnostic JSON.');
      }
      if (!mounted) return;
      setState(() {
        _data = decoded;
        _message = t('Scan finished. Review each section for details.',
            'Đã quét xong. Chọn từng danh mục để xem chi tiết.');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _message = t('Scan failed. Check the diagnostic core.',
            'Quét thất bại. Hãy kiểm tra diagnostic_core.');
      });
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  String _status(String key) {
    if (_running) return 'SCANNING';
    if (_data == null) return 'READY';
    switch (key) {
      case 'health': return _healthStatus();
      case 'cpu': return _data!['cpu'] != null ? 'PASS' : 'FAIL';
      case 'memory': return _data!['memory'] != null ? 'PASS' : 'FAIL';
      case 'storage': return (_data!['storage'] as List?)?.isNotEmpty == true ? 'PASS' : 'FAIL';
      case 'gpu': return (_data!['gpu'] as List?)?.isNotEmpty == true ? 'PASS' : 'WARN';
      case 'battery': return _data!['battery']?['detected'] == true ? 'PASS' : 'WARN';
      case 'network':
        final network = _data!['network'];
        final s = network?['overall_status']?.toString() ?? 'FAILED';
        if (s == 'PASS') return 'PASS';
        if (s == 'PARTIAL') return 'WARN';
        return 'FAIL';
      case 'system': return (_data!['computer'] != null || _data!['bios'] != null) ? 'PASS' : 'WARN';
      case 'thermals': return 'WARN';
      default: return 'READY';
    }
  }

  String _statusLabel(String status) => switch (status) {
        'PASS' => t('PASS', 'ĐẠT'),
        'WARN' => t('WARN', 'LƯU Ý'),
        'FAIL' => t('FAIL', 'LỖI'),
        'SCANNING' => t('SCANNING', 'ĐANG QUÉT'),
        'UNKNOWN' => t('UNKNOWN', 'CHƯA RÕ'),
        _ => t('READY', 'SẴN SÀNG'),
      };

  Color _statusColor(String status) => switch (status) {
        'PASS' => const Color(0xFF4ADE80),
        'WARN' => const Color(0xFFFBBF24),
        'FAIL' => const Color(0xFFFB7185),
        'SCANNING' => _blue,
        'UNKNOWN' => const Color(0xFF8291A8),
        _ => const Color(0xFF8291A8),
      };

  List<Map<String, String>> _healthChecks() {
    if (_data == null) return [];
    final checks = <Map<String, String>>[];
    void add(String name, String status, String description) => checks.add({
      'name': name, 'status': status, 'description': description,
    });
    final cpu = _data!['cpu'];
    if (cpu is Map) {
      final status = cpu['verification_status']?.toString() ?? 'UNVERIFIED';
      add(t('CPU identity', 'Định danh CPU'),
          status == 'CONSISTENT' ? 'PASS' : status == 'MISMATCH' ? 'WARN' : 'UNKNOWN',
          status == 'CONSISTENT'
              ? t('WMI and CPUID brand strings are consistent. This does not prove authenticity.', 'Tên CPU từ WMI và CPUID nhất quán. Điều này không chứng minh CPU là hàng thật.')
              : status == 'MISMATCH'
                  ? t('WMI and CPUID names differ; inspect manually.', 'Tên CPU từ WMI và CPUID khác nhau; cần kiểm tra thủ công.')
                  : t('Insufficient CPU verification data.', 'Chưa đủ dữ liệu để xác minh CPU.'));
    } else {
      add(t('CPU identity', 'Định danh CPU'), 'UNKNOWN', t('CPU data unavailable.', 'Không có dữ liệu CPU.'));
    }
    final disks = _data!['storage'];
    if (disks is List && disks.isNotEmpty) {
      for (final disk in disks) {
        if (disk is! Map) continue;
        final total = disk['total_gb'];
        final free = disk['available_gb'];
        final name = disk['mount_point']?.toString() ?? t('Disk', 'Ổ đĩa');
        if (total is num && free is num && total > 0 && free >= 0) {
          final fraction = free / total;
          add(name, fraction < 0.10 ? 'WARN' : 'PASS',
              t('Free space: $free / $total GB. Capacity alone is not a disk-health test.', 'Dung lượng trống: $free / $total GB. Dung lượng không phản ánh sức khỏe vật lý của ổ.'));
        } else {
          add(name, 'UNKNOWN', t('Disk capacity data unavailable.', 'Không đủ dữ liệu dung lượng ổ đĩa.'));
        }
      }
    } else {
      add(t('Storage', 'Lưu trữ'), 'UNKNOWN', t('No storage information.', 'Không có dữ liệu ổ đĩa.'));
    }
    final memory = _data!['memory'];
    if (memory is Map && memory['total_mb'] is num && (memory['total_mb'] as num) > 0) {
      add(t('Memory reporting', 'Dữ liệu RAM'), 'PASS',
          t('Memory capacity is readable; this is not a RAM integrity test.', 'Đọc được dung lượng RAM; đây không phải kiểm tra lỗi RAM.'));
    } else {
      add(t('Memory reporting', 'Dữ liệu RAM'), 'UNKNOWN', t('Memory capacity unavailable.', 'Không đọc được dung lượng RAM.'));
    }
    final computer = _data!['computer'];
    final bios = _data!['bios'];
    final hasModel = computer is Map && (computer['model']?.toString().trim().isNotEmpty ?? false);
    final hasBios = bios is Map && (bios['version']?.toString().trim().isNotEmpty ?? false);
    add(t('System identity', 'Định danh hệ thống'), hasModel && hasBios ? 'PASS' : 'UNKNOWN',
        hasModel && hasBios
            ? t('Computer model and BIOS version are available.', 'Đọc được model máy và phiên bản BIOS.')
            : t('Model or BIOS version is unavailable.', 'Thiếu model máy hoặc phiên bản BIOS.'));
    return checks;
  }

  String _healthStatus() {
    final checks = _healthChecks();
    if (checks.isEmpty) return 'UNKNOWN';
    if (checks.any((c) => c['status'] == 'FAIL')) return 'FAIL';
    if (checks.any((c) => c['status'] == 'WARN')) return 'WARN';
    if (checks.any((c) => c['status'] == 'UNKNOWN')) return 'UNKNOWN';
    return 'PASS';
  }

  Widget _healthPage() {
    final checks = _healthChecks();
    final passed = checks.where((c) => c['status'] == 'PASS').length;
    final evaluated = checks.where((c) => c['status'] == 'PASS' || c['status'] == 'WARN' || c['status'] == 'FAIL').length;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(26),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t('HEALTH & TRUST CENTER', 'TRUNG TÂM SỨC KHỎE & ĐỘ TIN CẬY'),
            style: const TextStyle(color: _cyan, fontSize: 12, letterSpacing: 1.5, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        Text(t('Evidence first. No fake scores.', 'Dựa trên dữ liệu thật. Không tạo điểm giả.'),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 18),
        _panelCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.health_and_safety_rounded, color: _cyan), const SizedBox(width: 12),
            Expanded(child: Text(t('Overall assessment', 'Đánh giá tổng hợp'), style: const TextStyle(fontWeight: FontWeight.bold))),
            _statusPill(_data == null ? 'READY' : _healthStatus())]),
          const SizedBox(height: 14),
          Text(_data == null ? t('Run a scan to see health checks.', 'Hãy quét để xem kết quả kiểm tra.')
              : t('$passed / $evaluated evaluated checks passed; ${checks.length - evaluated} unknown.',
                  '$passed / $evaluated phép kiểm tra có kết luận đạt; ${checks.length - evaluated} chưa rõ.'),
              style: const TextStyle(color: Color(0xFFB7C5D8))),
          const SizedBox(height: 12),
          Text(t('This is an evidence summary, not a hardware warranty or full integrity test.',
              'Đây là tổng hợp bằng chứng, không phải bảo đảm phần cứng hay kiểm tra toàn diện.'),
              style: const TextStyle(fontSize: 11, color: Color(0xFF8EA2BB))),
        ])),
        const SizedBox(height: 14),
        for (final check in checks) ...[
          _panelCard(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(check['name']!, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(check['description']!, style: const TextStyle(color: Color(0xFFB7C5D8), height: 1.5)),
            ])),
            const SizedBox(width: 12),
            _statusPill(check['status']!),
          ])),
          const SizedBox(height: 12),
        ],
        _repairCenter(),
      ]),
    );
  }

  String _detail(String key) {
    if (_data == null) {
      return switch (key) {
        'thermals' => t('Temperature sensor readings are not implemented.', 'Chưa tích hợp đọc cảm biến nhiệt độ.'),
        _ => t('Run a diagnostic scan to inspect this component.', 'Chạy chẩn đoán để kiểm tra thành phần này.'),
      };
    }
    switch (key) {
      case 'cpu':
        final cpu = _data!['cpu'];
        if (cpu == null) return t('No CPU data', 'Không có dữ liệu CPU');
        return '${cpu['name'] ?? 'Unknown'}\n'
            '${cpu['core_count'] ?? '--'} ${t('cores', 'nhân')}  •  ${cpu['frequency_mhz'] ?? '--'} MHz\n'
            'CPUID: ${cpu['cpuid_name'] ?? 'Unavailable'}\n'
            '${t('Verification', 'Xác minh')}: ${cpu['verification_status'] ?? 'UNVERIFIED'}';
      case 'memory':
        final m = _data!['memory'];
        if (m == null) return t('No memory data', 'Không có dữ liệu RAM');
        return '${m['used_mb'] ?? '--'} MB ${t('used', 'đã dùng')} / ${m['total_mb'] ?? '--'} MB ${t('total', 'tổng')}\n'
            '${m['available_mb'] ?? '--'} MB ${t('available', 'còn trống')}';
      case 'storage':
        final disks = _data!['storage'] as List? ?? [];
        if (disks.isEmpty) return t('No storage data', 'Không có dữ liệu ổ đĩa');
        return disks.map((d) => '${d['mount_point'] ?? ''}  •  ${d['name'] ?? ''}\n'
            '${d['available_gb'] ?? '--'} GB ${t('free of', 'trống / tổng')} ${d['total_gb'] ?? '--'} GB').join('\n\n');
      case 'gpu':
        final gpus = _data!['gpu'] as List? ?? [];
        if (gpus.isEmpty) return t('No GPU detected', 'Không phát hiện GPU');
        return gpus.map((g) => '${g['name'] ?? 'Unknown GPU'}\n${g['vram_mb'] ?? '--'} MB VRAM ${t('reported', 'được báo cáo')}').join('\n\n');
      case 'battery':
        final b = _data!['battery'];
        if (b == null || b['detected'] != true) return t('No battery detected (common on desktops).', 'Không phát hiện pin (thường gặp trên máy bàn).');
        final runtime = b['estimated_runtime_minutes'];
        final valid = runtime is int && runtime >= 0 && runtime <= 10080;
        return '${t('Charge', 'Mức pin')}: ${b['charge_percent'] ?? '--'}%'
            '${valid ? '\n${t('Estimated runtime', 'Thời lượng ước tính')}: ${runtime ~/ 60}h ${runtime % 60}m' : ''}';
      case 'network':
        final n = _data!['network'];
        if (n == null) return t('Network diagnostics not available', 'Không có dữ liệu chẩn đoán mạng');
        final checks = n['checks'] as List? ?? [];
        final lines = <String>[];
        for (final raw in checks) {
          if (raw is! Map) continue;
          final status = raw['status']?.toString() ?? 'UNKNOWN';
          final latency = raw['latency_ms'];
          lines.add('${raw['name'] ?? 'Endpoint'}  •  $status${latency == null ? '' : '  •  ${latency} ms'}\n${raw['detail'] ?? ''}');
        }
        lines.add('${t('VPN NOTE', 'LƯU Ý VPN')}: ${n['vpn_warning'] ?? ''}');
        lines.add('${n['note'] ?? ''}');
        return lines.join('\n\n');
      case 'system':
        final c = _data!['computer'];
        final b = _data!['bios'];
        if (c == null && b == null) return t('No system information', 'Không có thông tin hệ thống');
        var date = b?['release_date']?.toString() ?? '';
        if (date.length >= 8 && RegExp(r'^\d{8}$').hasMatch(date.substring(0, 8))) {
          final d = date.substring(0, 8);
          date = '${d.substring(6, 8)}/${d.substring(4, 6)}/${d.substring(0, 4)}';
        }
        return '${c?['manufacturer'] ?? 'Unknown manufacturer'} ${c?['model'] ?? 'Unknown model'}\n'
            'BIOS: ${b?['manufacturer'] ?? 'Unknown'} ${b?['version'] ?? 'Unknown'}${date.isEmpty ? '' : '  •  $date'}';
      case 'thermals':
        return t('Temperature readings are not implemented in this version. No temperature value is fabricated.', 'Phiên bản này chưa đọc được cảm biến nhiệt độ. Ứng dụng không tự tạo số đo giả.');
      default: return '';
    }
  }

  double? _memoryRatio() {
    final m = _data?['memory'];
    if (m is! Map) return null;
    final total = m['total_mb'];
    final used = m['used_mb'];
    if (total is! num || used is! num || total <= 0) return null;
    return (used / total).clamp(0.0, 1.0).toDouble();
  }

  Widget _statusPill(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withOpacity(.38)),
      ),
      child: Text(_statusLabel(status), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: .8)),
    );
  }

  Widget _sidebarItem(_Section section) {
    final selected = section.id == _selected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
        color: selected ? const Color(0xFF15334B) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _selected = section.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? _blue.withOpacity(.45) : Colors.transparent),
            ),
            child: Row(children: [
              Icon(section.icon, color: selected ? _cyan : const Color(0xFF8EA2BB), size: 21),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(_vietnamese ? section.vi : section.en, style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w600, fontSize: 13, color: selected ? Colors.white : const Color(0xFFC3D0E0))),
                const SizedBox(height: 3),
                Text(_statusLabel(_status(section.id)), style: TextStyle(fontSize: 9, color: _statusColor(_status(section.id)), letterSpacing: .7, fontWeight: FontWeight.bold)),
              ])),
              if (selected) const Icon(Icons.chevron_right_rounded, color: _cyan, size: 19),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _panelCard({Key? key, required Widget child, EdgeInsets padding = const EdgeInsets.all(20)}) => Container(
        key: key,
        padding: padding,
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF26354C)),
          boxShadow: const [BoxShadow(color: Color(0x18000000), blurRadius: 22, offset: Offset(0, 8))],
        ),
        child: child,
      );

  Widget _overview() {
    final passed = _sections.where((s) => s.id != 'overview' && _status(s.id) == 'PASS').length;
    final warns = _sections.where((s) => s.id != 'overview' && _status(s.id) == 'WARN').length;
    final fails = _sections.where((s) => s.id != 'overview' && _status(s.id) == 'FAIL').length;
    final ratio = _memoryRatio();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('SYSTEM OVERVIEW', 'TỔNG QUAN HỆ THỐNG'), style: const TextStyle(color: _cyan, fontSize: 11, letterSpacing: 2.2, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(t('Your machine.\nUnder the hood.', 'Toàn cảnh\nbên trong máy.'), style: const TextStyle(fontSize: 31, height: 1.12, fontWeight: FontWeight.w900, letterSpacing: -.7)),
            const SizedBox(height: 10),
            Text(_message, style: const TextStyle(color: Color(0xFF9BAEC5), fontSize: 13)),
          ])),
          const SizedBox(width: 12),
          Container(width: 76, height: 76, decoration: BoxDecoration(shape: BoxShape.circle, color: _blue.withOpacity(.1), border: Border.all(color: _blue.withOpacity(.35))), child: const Icon(Icons.memory_rounded, size: 38, color: _cyan)),
        ]),
        const SizedBox(height: 24),
        if (_running) ...[
          _panelCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _cyan)), const SizedBox(width: 12), Text(t('Scanning diagnostic core…', 'Đang chạy chẩn đoán…'), style: const TextStyle(fontWeight: FontWeight.bold))]),
            const SizedBox(height: 16),
            const ClipRRect(borderRadius: BorderRadius.all(Radius.circular(20)), child: LinearProgressIndicator(minHeight: 6, backgroundColor: Color(0xFF243247), color: _blue)),
            const SizedBox(height: 8),
            Text(t('Progress is indeterminate while Windows collects the hardware report.', 'Thanh tiến trình chạy trong lúc Windows thu thập báo cáo phần cứng.'), style: const TextStyle(fontSize: 11, color: Color(0xFF8EA2BB))),
          ])),
          const SizedBox(height: 16),
        ],
        LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth;
          final count = width > 780 ? 4 : width > 470 ? 2 : 1;
          final items = <(String, String, IconData, Color)>[
            (t('Passed', 'Đạt'), '$passed', Icons.check_circle_outline_rounded, const Color(0xFF4ADE80)),
            (t('Warnings', 'Lưu ý'), '$warns', Icons.warning_amber_rounded, const Color(0xFFFBBF24)),
            (t('Failures', 'Lỗi'), '$fails', Icons.error_outline_rounded, const Color(0xFFFB7185)),
            (t('Sections', 'Danh mục'), '${_sections.length - 1}', Icons.grid_view_rounded, _cyan),
          ];
          return GridView.builder(
            itemCount: items.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: count, crossAxisSpacing: 12, mainAxisSpacing: 12, mainAxisExtent: 112),
            itemBuilder: (context, index) {
              final item = items[index];
              return _panelCard(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Icon(item.$3, color: item.$4, size: 22),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(item.$2, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900)), const SizedBox(width: 9), Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(item.$1, style: const TextStyle(fontSize: 11, color: Color(0xFF9BAEC5)))))])
              ]));
            },
          );
        }),
        const SizedBox(height: 14),
        if (ratio != null) _panelCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.memory_rounded, color: _cyan), const SizedBox(width: 10), Expanded(child: Text(t('Memory utilization', 'Mức sử dụng RAM'), style: const TextStyle(fontWeight: FontWeight.w800))), Text('${(ratio * 100).round()}%', style: const TextStyle(color: _cyan, fontWeight: FontWeight.w900))]),
          const SizedBox(height: 14),
          ClipRRect(borderRadius: BorderRadius.circular(12), child: LinearProgressIndicator(value: ratio, minHeight: 8, backgroundColor: const Color(0xFF26354C), color: ratio > .85 ? const Color(0xFFFBBF24) : _blue)),
          const SizedBox(height: 8),
          Text(_detail('memory'), style: const TextStyle(color: Color(0xFF9BAEC5), fontSize: 12)),
        ])),
        const SizedBox(height: 22),
        Text(t('DIAGNOSTIC MODULES', 'CÁC DANH MỤC CHẨN ĐOÁN'), style: const TextStyle(color: _cyan, fontSize: 10, letterSpacing: 1.8, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          final count = constraints.maxWidth > 850 ? 3 : constraints.maxWidth > 520 ? 2 : 1;
          final modules = _sections.where((s) => s.id != 'overview').toList();
          return GridView.builder(
            itemCount: modules.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: count, crossAxisSpacing: 12, mainAxisSpacing: 12, mainAxisExtent: 118),
            itemBuilder: (context, index) {
              final section = modules[index];
              final status = _status(section.id);
              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => setState(() => _selected = section.id),
                child: _panelCard(padding: const EdgeInsets.all(15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Icon(section.icon, color: _cyan, size: 20), const Spacer(), _statusPill(status)]),
                  const Spacer(),
                  Text(_vietnamese ? section.vi : section.en, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(_vietnamese ? section.subtitleVi : section.subtitleEn, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Color(0xFF91A4BC))),
                ])),
              );
            },
          );
        }),
        if (_error != null) ...[
          const SizedBox(height: 16),
          _panelCard(child: Text(_error!, style: const TextStyle(color: Color(0xFFFB7185), fontSize: 12))),
        ],
      ]),
    );
  }

  Widget _detailPage() {
    final section = selectedSection;
    final status = _status(section.id);
    final detail = _detail(section.id);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_vietnamese ? 'TRUNG TÂM CHẨN ĐOÁN' : 'DIAGNOSTIC CENTER', style: const TextStyle(color: _cyan, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 58, height: 58, decoration: BoxDecoration(color: _blue.withOpacity(.12), borderRadius: BorderRadius.circular(17), border: Border.all(color: _blue.withOpacity(.28))), child: Icon(section.icon, size: 30, color: _cyan)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_vietnamese ? section.vi : section.en, style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: -.5)),
            const SizedBox(height: 5),
            Text(_vietnamese ? section.subtitleVi : section.subtitleEn, style: const TextStyle(color: Color(0xFF9BAEC5), fontSize: 12)),
          ])),
          _statusPill(status),
        ]),
        const SizedBox(height: 24),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, .025), end: Offset.zero).animate(animation), child: child)),
          child: _panelCard(key: ValueKey(section.id), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Icon(Icons.article_outlined, color: _cyan, size: 20), const SizedBox(width: 9), Text(_vietnamese ? 'KẾT QUẢ CHI TIẾT' : 'DETAILED REPORT', style: const TextStyle(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w900, color: _cyan))]),
            const SizedBox(height: 18),
            SelectableText(detail, style: const TextStyle(fontSize: 14, height: 1.8, color: Color(0xFFD1DCE9))),
          ])),
        ),
        if (section.id == 'network') ...[
          const SizedBox(height: 14),
          _panelCard(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.info_outline_rounded, color: Color(0xFFFBBF24)), const SizedBox(width: 12), Expanded(child: Text(t('These checks test DNS/TCP connectivity only. They do not measure true download/upload speed or ICMP ping. A failed endpoint alone does not prove that the whole Internet is down.', 'Các phép thử này chỉ kiểm tra DNS/kết nối TCP. Chúng chưa đo tốc độ tải xuống/tải lên thực tế hoặc ping ICMP. Một endpoint thất bại không có nghĩa toàn bộ Internet bị mất.'), style: const TextStyle(color: Color(0xFFB7C5D8), height: 1.6, fontSize: 12)))])),
        ],
        if (section.id == 'thermals') ...[
          const SizedBox(height: 14),
          _panelCard(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.warning_amber_rounded, color: Color(0xFFFBBF24)), const SizedBox(width: 12), Expanded(child: Text(t('Temperature sensor reading is not implemented yet. This section is marked WARN instead of showing invented values.', 'Tính năng đọc cảm biến nhiệt độ chưa được triển khai. Danh mục này được đánh dấu LƯU Ý thay vì hiển thị số liệu giả.'), style: const TextStyle(color: Color(0xFFB7C5D8), height: 1.6, fontSize: 12)))])),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: Row(children: [
        Container(
          width: 252,
          decoration: const BoxDecoration(color: Color(0xFF0B1220), border: Border(right: BorderSide(color: Color(0xFF202D42)))),
          child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(18, 22, 18, 18), child: Row(children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(gradient: const LinearGradient(colors: [_blue, Color(0xFF2563EB)]), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.memory_rounded, color: Colors.white, size: 25)),
              const SizedBox(width: 11),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('PC DIAGNOSTICS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: .8)), SizedBox(height: 4), Text('SYSTEM // TOOLKIT', style: TextStyle(color: Color(0xFF71849F), fontSize: 9, letterSpacing: 1.1))])),
            ])),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: Divider(color: Color(0xFF202D42), height: 1)),
            Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 9), child: Align(alignment: Alignment.centerLeft, child: Text(t('WORKSPACE', 'DANH MỤC'), style: const TextStyle(color: Color(0xFF6F849F), fontSize: 9, letterSpacing: 1.8, fontWeight: FontWeight.w900)))),
            Expanded(child: ListView(padding: const EdgeInsets.only(bottom: 12), children: _sections.map(_sidebarItem).toList())),
            Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 14), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFF26354C))), child: Row(children: [const Icon(Icons.circle, size: 8, color: Color(0xFF4ADE80)), const SizedBox(width: 9), Expanded(child: Text(_running ? t('Diagnostic running', 'Đang chẩn đoán') : t('Diagnostic core', 'Bộ chẩn đoán'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))), Text(_running ? 'RUN' : 'V1', style: const TextStyle(color: _cyan, fontSize: 10, fontWeight: FontWeight.w900))]))),
          ]),
        ),
        Expanded(child: Column(children: [
          Container(height: 68, padding: const EdgeInsets.symmetric(horizontal: 25), decoration: const BoxDecoration(color: _bg, border: Border(bottom: BorderSide(color: Color(0xFF202D42)))), child: Row(children: [
            Expanded(child: Row(children: [const Icon(Icons.terminal_rounded, size: 19, color: _cyan), const SizedBox(width: 10), Text(_vietnamese ? selectedSection.vi : selectedSection.en, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)), const SizedBox(width: 12), Container(width: 4, height: 4, decoration: const BoxDecoration(color: _blue, shape: BoxShape.circle)), const SizedBox(width: 8), Text(_running ? t('SCANNING', 'ĐANG QUÉT') : t('LOCAL DIAGNOSTICS', 'CHẨN ĐOÁN CỤC BỘ'), style: const TextStyle(color: Color(0xFF71849F), fontSize: 9, letterSpacing: 1.2, fontWeight: FontWeight.w800))])),
            OutlinedButton.icon(onPressed: () => setState(() => _vietnamese = !_vietnamese), icon: const Icon(Icons.translate_rounded, size: 16), label: Text(_vietnamese ? 'VI / EN' : 'EN / VI'), style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFC8D8EA), side: const BorderSide(color: Color(0xFF2B3B53)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)))),
            const SizedBox(width: 10),
            FilledButton.icon(onPressed: _running || _repairBusy ? null : _runDiagnostic, icon: _running ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.play_arrow_rounded, size: 19), label: Text(_running ? t('Scanning', 'Đang quét') : t('Run scan', 'Quét ngay')), style: FilledButton.styleFrom(backgroundColor: const Color(0xFF147CB5), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)))),
          ])),
          if (_running) const LinearProgressIndicator(minHeight: 3, backgroundColor: Color(0xFF172338), color: _cyan),
          Expanded(child: _selected == 'overview' ? _overview() : _selected == 'health' ? _healthPage() : _detailPage()),
          Container(height: 31, padding: const EdgeInsets.symmetric(horizontal: 18), decoration: const BoxDecoration(color: Color(0xFF0B1220), border: Border(top: BorderSide(color: Color(0xFF202D42)))), child: Row(children: [const Icon(Icons.shield_outlined, size: 13, color: Color(0xFF71849F)), const SizedBox(width: 7), Text(t('LOCAL REPORT  •  No telemetry added by this UI', 'BÁO CÁO CỤC BỘ  •  Giao diện không thêm telemetry'), style: const TextStyle(fontSize: 9, color: Color(0xFF71849F))), const Spacer(), Text(t('HARDWARE + NETWORK', 'PHẦN CỨNG + MẠNG'), style: const TextStyle(fontSize: 9, letterSpacing: 1.2, color: Color(0xFF71849F), fontWeight: FontWeight.w800))])),
        ])),
      ])),
    );
  }
}
