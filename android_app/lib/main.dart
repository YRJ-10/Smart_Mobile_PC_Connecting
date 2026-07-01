import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const SmartMpcApp());
}

class SmartMpcApp extends StatelessWidget {
  const SmartMpcApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Smart MPC',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2DD4BF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF101417),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _prefs = MethodChannel('smart_mpc/preferences');

  final _baseUrlController =
      TextEditingController(text: 'http://192.168.1.10:8765');
  final _pairingTokenController = TextEditingController();
  final _urlController = TextEditingController(text: 'https://example.com');
  final _clipboardController = TextEditingController();

  bool _busy = false;
  int _tabIndex = 0;
  String _status = 'Ready';
  String _deviceId = '';
  String _deviceToken = '';
  String _pcId = '';
  String _deviceName = 'Android device';
  String _pcName = '';
  List<String> _baseUrls = const [];
  List<_PcRequestFile> _requestFiles = const [];

  bool get _isTrusted =>
      _deviceId.isNotEmpty && _deviceToken.isNotEmpty && _pcId.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _prefs.setMethodCallHandler(_handleNativeCall);
    _bootstrap();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _pairingTokenController.dispose();
    _urlController.dispose();
    _clipboardController.dispose();
    super.dispose();
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'nativeStatus') {
      if (mounted) {
        setState(() =>
            _status = call.arguments?.toString() ?? 'Native action finished');
      }
    }
    return null;
  }

  Future<void> _bootstrap() async {
    await _loadConfig();
    _ensureDeviceId();
  }

  Future<void> _loadConfig() async {
    try {
      final config =
          await _prefs.invokeMapMethod<String, dynamic>('loadConfig') ?? {};
      if (!mounted) return;
      setState(() {
        final baseUrl = config['baseUrl']?.toString() ?? '';
        if (baseUrl.isNotEmpty) _baseUrlController.text = baseUrl;
        _pairingTokenController.text = config['pairingToken']?.toString() ?? '';
        _deviceId = config['deviceId']?.toString() ?? '';
        _deviceToken = config['deviceToken']?.toString() ?? '';
        _pcId = config['pcId']?.toString() ?? '';
        _deviceName = config['deviceName']?.toString() ?? 'Android device';
      });
    } catch (error) {
      if (mounted) setState(() => _status = 'Config unavailable: $error');
    }
  }

  Future<void> _saveConfig({bool showStatus = false}) async {
    await _prefs.invokeMethod('saveConfig', {
      'baseUrl': _normalizedBaseUrl(),
      'pairingToken': _pairingTokenController.text.trim(),
      'deviceId': _deviceId,
      'deviceToken': _deviceToken,
      'pcId': _pcId,
    });
    if (showStatus && mounted) setState(() => _status = 'Config saved');
  }

  Future<void> _clearTrust() async {
    await _run('Clearing trust', () async {
      setState(() {
        _deviceToken = '';
        _pcId = '';
      });
      await _saveConfig();
      return 'Phone trust cleared locally';
    });
  }

  Future<void> _testHealth() async {
    await _run('Checking server', () async {
      final result = await _getJson('/health');
      final app = result['app']?.toString() ?? 'PC server';
      final pcName = result['pc_name']?.toString() ?? '';
      setState(() {
        _pcName = pcName;
        _pcId = result['pc_id']?.toString() ?? _pcId;
      });
      await _saveConfig();
      return pcName.isEmpty
          ? '$app is reachable'
          : '$app on $pcName is reachable';
    });
  }

  Future<void> _pairWithPc() async {
    await _run('Pairing phone', () async {
      _ensureDeviceId();
      final result = await _postJson(
        '/api/devices/register',
        {
          'device_id': _deviceId,
          'device_name': _deviceName,
          'client': 'smart_mpc_android',
        },
        pairing: true,
      );

      setState(() {
        _pcId = result['pc_id']?.toString() ?? '';
        _deviceId = result['device_id']?.toString() ?? _deviceId;
        _deviceToken = result['device_token']?.toString() ?? '';
      });
      await _saveConfig();
      return _isTrusted ? 'Phone trusted' : 'Pairing response incomplete';
    });
  }

  Future<void> _loadPairInfo() async {
    await _run('Loading pair info', () async {
      final result = await _getJson('/pair');
      final urls = (result['base_urls'] as List<dynamic>? ?? [])
          .map((value) => value.toString())
          .where((value) => value.isNotEmpty)
          .toList();
      setState(() {
        _pcName = result['pc_name']?.toString() ?? '';
        _pcId = result['pc_id']?.toString() ?? _pcId;
        _baseUrls = urls;
      });
      if (urls.isNotEmpty) {
        _baseUrlController.text = urls.first;
        await _saveConfig();
      }
      return urls.isEmpty
          ? 'Pair info loaded'
          : 'Found ${urls.length} PC address(es)';
    });
  }

  Future<void> _run(String pending, Future<String> Function() task) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = pending;
    });

    try {
      final message = await task();
      if (mounted) {
        setState(() => _status = message);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'Error: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _sendUrl() async {
    await _run('Opening URL on PC', () async {
      await _postJson('/api/intent', {
        'type': 'url',
        'source': 'android',
        'payload': {'url': _urlController.text.trim()},
      });
      return 'URL sent to PC';
    });
  }

  Future<void> _readPhoneClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    setState(() {
      _clipboardController.text = data?.text ?? '';
      _status = _clipboardController.text.isEmpty
          ? 'Phone clipboard is empty'
          : 'Phone clipboard loaded';
    });
  }

  Future<void> _sendClipboard() async {
    await _run('Sending clipboard to PC', () async {
      await _postJson('/api/intent', {
        'type': 'clipboard',
        'source': 'android',
        'payload': {'text': _clipboardController.text},
      });
      return 'Clipboard sent to PC';
    });
  }

  Future<void> _pullPcClipboard() async {
    await _run('Reading PC clipboard', () async {
      final result = await _getJson('/api/clipboard', authorized: true);
      final text = result['text']?.toString() ?? '';
      await Clipboard.setData(ClipboardData(text: text));
      setState(() => _clipboardController.text = text);
      return text.isEmpty
          ? 'PC clipboard is empty'
          : 'PC clipboard copied to phone';
    });
  }

  Future<void> _sendCommand(String commandId) async {
    await _run('Sending command', () async {
      await _postJson('/api/intent', {
        'type': 'command',
        'source': 'android',
        'payload': {'command_id': commandId},
      });
      return 'Command sent: $commandId';
    });
  }

  Future<void> _pickAndUploadFiles() async {
    if (!_isTrusted) {
      setState(() => _status = 'Trust this phone first');
      return;
    }
    await _prefs.invokeMethod('pickAndUploadFiles', {
      'baseUrl': _normalizedBaseUrl(),
      'deviceId': _deviceId,
      'deviceToken': _deviceToken,
    });
    setState(() => _status = 'Choose file(s) to send');
  }

  Future<void> _loadRequestFiles() async {
    await _run('Loading PC files', () async {
      final result = await _getJson('/api/request-files', authorized: true);
      final files = (result['files'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(_PcRequestFile.fromJson)
          .toList();
      setState(() => _requestFiles = files);
      return files.isEmpty
          ? 'No PC files available'
          : '${files.length} PC file(s)';
    });
  }

  Future<void> _downloadRequestFile(_PcRequestFile file) async {
    await _run('Requesting ${file.name}', () async {
      final url =
          '${_normalizedBaseUrl()}/api/request-files/download?filename=${Uri.encodeQueryComponent(file.name)}';
      await _prefs.invokeMethod('downloadToDownloads', {
        'url': url,
        'filename': file.name,
        'deviceId': _deviceId,
        'deviceToken': _deviceToken,
      });
      return 'Download started: ${file.name}';
    });
  }

  Future<Map<String, dynamic>> _getJson(String path,
      {bool authorized = false}) async {
    final client = HttpClient();
    try {
      final request =
          await client.getUrl(_uri(path)).timeout(const Duration(seconds: 5));
      if (authorized) {
        request.headers.add('X-Device-Id', _deviceId);
        request.headers.add('X-Device-Token', _deviceToken);
      }
      final response =
          await request.close().timeout(const Duration(seconds: 8));
      return _readJson(response);
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, Object?> body, {
    bool pairing = false,
  }) async {
    final client = HttpClient();
    try {
      final request =
          await client.postUrl(_uri(path)).timeout(const Duration(seconds: 5));
      request.headers.contentType = ContentType.json;
      if (pairing) {
        request.headers
            .add('X-Pairing-Token', _pairingTokenController.text.trim());
      } else if (_isTrusted) {
        request.headers.add('X-Device-Id', _deviceId);
        request.headers.add('X-Device-Token', _deviceToken);
      }
      request.write(jsonEncode(body));
      final response =
          await request.close().timeout(const Duration(seconds: 8));
      return _readJson(response);
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _readJson(HttpClientResponse response) async {
    final text = await response.transform(utf8.decoder).join();
    final decoded = text.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(text) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          decoded['error']?.toString() ?? 'HTTP ${response.statusCode}');
    }
    if (decoded['ok'] == false) {
      throw Exception(decoded['error']?.toString() ?? 'Request failed');
    }
    return decoded;
  }

  Uri _uri(String path) => Uri.parse('${_normalizedBaseUrl()}$path');

  String _normalizedBaseUrl() {
    return _baseUrlController.text.trim().replaceAll(RegExp(r'/+$'), '');
  }

  void _ensureDeviceId() {
    if (_deviceId.isNotEmpty) return;
    final random = Random.secure();
    final suffix = List<int>.generate(8, (_) => random.nextInt(256))
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    setState(() =>
        _deviceId = 'android-${DateTime.now().millisecondsSinceEpoch}-$suffix');
    _saveConfig();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildConnectPage(),
      _buildActionsPage(),
      _PlaceholderPage(
        title: 'Remote',
        icon: Icons.touch_app_rounded,
        lines: const [
          'Trackpad, keyboard, voice typing, and media controls land here in later phases.'
        ],
      ),
      _PlaceholderPage(
        title: 'Mirror',
        icon: Icons.screenshot_monitor_rounded,
        lines: const [
          'Screen mirror, touch mapping, and audio controls land here in later phases.'
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart MPC'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: _StateChip(
                label: _isTrusted ? 'Trusted' : 'Untrusted',
                active: _isTrusted,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(child: pages[_tabIndex]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.lan_rounded), label: 'Connect'),
          NavigationDestination(
              icon: Icon(Icons.bolt_rounded), label: 'Actions'),
          NavigationDestination(
              icon: Icon(Icons.touch_app_rounded), label: 'Remote'),
          NavigationDestination(
              icon: Icon(Icons.screenshot_monitor_rounded), label: 'Mirror'),
        ],
      ),
    );
  }

  Widget _buildConnectPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _HeroPanel(
          trusted: _isTrusted,
          pcName: _pcName,
          status: _status,
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'PC Server',
          child: Column(
            children: [
              TextField(
                controller: _baseUrlController,
                decoration: const InputDecoration(
                  labelText: 'PC Address',
                  hintText: 'http://192.168.1.10:8765',
                  prefixIcon: Icon(Icons.dns_rounded),
                ),
                keyboardType: TextInputType.url,
                onSubmitted: (_) => _saveConfig(showStatus: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pairingTokenController,
                decoration: const InputDecoration(
                  labelText: 'Pairing Token',
                  prefixIcon: Icon(Icons.key_rounded),
                ),
                obscureText: true,
                onSubmitted: (_) => _saveConfig(showStatus: true),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _testHealth,
                    icon: const Icon(Icons.favorite_rounded),
                    label: const Text('Health'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _loadPairInfo,
                    icon: const Icon(Icons.search_rounded),
                    label: const Text('Pair Info'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _pairWithPc,
                    icon: const Icon(Icons.verified_user_rounded),
                    label: const Text('Trust Phone'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _busy ? null : () => _saveConfig(showStatus: true),
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Device',
          child: Column(
            children: [
              _InfoRow(label: 'Phone', value: _deviceName),
              _InfoRow(label: 'Device ID', value: _deviceId),
              _InfoRow(label: 'PC ID', value: _pcId),
              _InfoRow(
                  label: 'Device Token',
                  value:
                      _deviceToken.isEmpty ? 'Not trusted' : 'Saved locally'),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy || !_isTrusted ? null : _clearTrust,
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('Clear Local Trust'),
                ),
              ),
            ],
          ),
        ),
        if (_baseUrls.isNotEmpty) ...[
          const SizedBox(height: 14),
          _SectionCard(
            title: 'PC Addresses',
            child: Column(
              children: _baseUrls
                  .map(
                    (url) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.link_rounded),
                      title: Text(url),
                      onTap: () {
                        setState(() => _baseUrlController.text = url);
                        _saveConfig(showStatus: true);
                      },
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(
          title: 'Files',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed:
                        _busy || !_isTrusted ? null : _pickAndUploadFiles,
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('Send File'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy || !_isTrusted ? null : _loadRequestFiles,
                    icon: const Icon(Icons.folder_copy_rounded),
                    label: const Text('Request Files'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_requestFiles.isEmpty)
                const Text('No PC files loaded',
                    style: TextStyle(color: Color(0xFF9AA8AF)))
              else
                for (final file in _requestFiles)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.insert_drive_file_rounded),
                    title: Text(file.name),
                    subtitle: Text(_formatBytes(file.bytes)),
                    trailing: IconButton(
                      tooltip: 'Download',
                      onPressed:
                          _busy ? null : () => _downloadRequestFile(file),
                      icon: const Icon(Icons.download_rounded),
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'Clipboard',
          child: Column(
            children: [
              TextField(
                controller: _clipboardController,
                decoration: const InputDecoration(
                  labelText: 'Clipboard Text',
                  prefixIcon: Icon(Icons.content_paste_rounded),
                ),
                minLines: 2,
                maxLines: 5,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _readPhoneClipboard,
                    icon: const Icon(Icons.phone_android_rounded),
                    label: const Text('Read Phone'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy || !_isTrusted ? null : _sendClipboard,
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Send to PC'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy || !_isTrusted ? null : _pullPcClipboard,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Pull from PC'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'URL',
          child: Column(
            children: [
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'URL',
                  prefixIcon: Icon(Icons.public_rounded),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _busy || !_isTrusted ? null : _sendUrl,
                  icon: const Icon(Icons.open_in_browser_rounded),
                  label: const Text('Open on PC'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          title: 'PC Commands',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _CommandButton(
                  label: 'Open Inbox',
                  icon: Icons.inventory_2_rounded,
                  onTap: () => _sendCommand('open_inbox'),
                  busy: _busy,
                  trusted: _isTrusted),
              _CommandButton(
                  label: 'Downloads',
                  icon: Icons.folder_rounded,
                  onTap: () => _sendCommand('open_downloads'),
                  busy: _busy,
                  trusted: _isTrusted),
              _CommandButton(
                  label: 'Chrome',
                  icon: Icons.language_rounded,
                  onTap: () => _sendCommand('open_chrome'),
                  busy: _busy,
                  trusted: _isTrusted),
              _CommandButton(
                  label: 'Lock',
                  icon: Icons.lock_rounded,
                  onTap: () => _sendCommand('lock_pc'),
                  busy: _busy,
                  trusted: _isTrusted),
              _CommandButton(
                  label: 'Sleep',
                  icon: Icons.bedtime_rounded,
                  onTap: () => _sendCommand('sleep_pc'),
                  busy: _busy,
                  trusted: _isTrusted),
            ],
          ),
        ),
      ],
    );
  }
}

class _PcRequestFile {
  const _PcRequestFile({
    required this.name,
    required this.bytes,
  });

  final String name;
  final int bytes;

  factory _PcRequestFile.fromJson(Map<String, dynamic> json) {
    return _PcRequestFile(
      name: json['name']?.toString() ?? 'file',
      bytes: int.tryParse(json['bytes']?.toString() ?? '') ?? 0,
    );
  }
}

class _CommandButton extends StatelessWidget {
  const _CommandButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.busy,
    required this.trusted,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool busy;
  final bool trusted;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: busy || !trusted ? null : onTap,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(1)} GB';
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.trusted,
    required this.pcName,
    required this.status,
  });

  final bool trusted;
  final String pcName;
  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFF151B20),
        border: Border.all(color: const Color(0xFF253139)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: colors.primary.withOpacity(0.12),
                ),
                child: Icon(Icons.devices_rounded, color: colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trusted ? 'Ready for PC actions' : 'Connect to your PC',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(pcName.isEmpty ? 'Local Wi-Fi connection' : pcName),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(status),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFF151B20),
        border: Border.all(color: const Color(0xFF253139)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF65D6A6) : const Color(0xFFF2B56B);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.7)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            child:
                Text(label, style: const TextStyle(color: Color(0xFF9AA8AF))),
          ),
          Expanded(child: SelectableText(value.isEmpty ? '-' : value)),
        ],
      ),
    );
  }
}

class _PlaceholderPage extends StatelessWidget {
  const _PlaceholderPage({
    required this.title,
    required this.icon,
    required this.lines,
  });

  final String title;
  final IconData icon;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 14),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            for (final line in lines)
              Text(
                line,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF9AA8AF)),
              ),
          ],
        ),
      ),
    );
  }
}
