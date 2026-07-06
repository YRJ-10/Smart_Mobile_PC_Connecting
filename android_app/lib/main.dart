import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _prefs = MethodChannel('smart_mpc/preferences');
  static const int _actionsTab = 0;
  static const int _remoteTab = 1;
  static const int _mirrorTab = 2;
  static const int _connectTab = 3;

  final _baseUrlController =
      TextEditingController(text: 'http://192.168.1.10:8765');
  final _pairingTokenController = TextEditingController();
  final _urlController = TextEditingController(text: 'https://example.com');
  final _clipboardController = TextEditingController();
  final _liveTextController = TextEditingController();

  bool _busy = false;
  bool _remoteConnected = false;
  bool _audioEnabled = false;
  bool _mirrorConnected = false;
  bool _voiceListening = false;
  int _tabIndex = 0;
  String _status = 'Ready';
  String _remoteStatus = 'Remote disconnected';
  String _audioStatus = 'PC audio off';
  String _mirrorStatus = 'Mirror disconnected';
  String _deviceId = '';
  String _deviceToken = '';
  String _pcId = '';
  String _deviceName = 'Android device';
  String _pcName = '';
  String _quickAction = 'send_file';
  String _lastLiveText = '';
  String _lastRecognizedWords = '';
  Socket? _controlSocket;
  Socket? _screenSocket;
  Uint8List? _screenFrame;
  List<int> _screenBuffer = [];
  bool _screenHandshakeDone = false;
  late final stt.SpeechToText _speech;
  double _lastBottomInset = 0.0;
  DateTime _lastMirrorMoveTime = DateTime.now();
  final Set<int> _mirrorActivePointers = {};
  final Map<int, Offset> _pointerPositions = {};
  final Map<int, Offset> _pointerStartPositions = {};
  DateTime _pointerDownTime = DateTime.now();
  int _peakPointerCount = 0;
  double _accumulatedDx = 0;
  double _accumulatedDy = 0;
  DateTime _lastMoveTime = DateTime.now();
  static const int _audioPort = 8081;
  bool _autoConnectInFlight = false;
  DateTime? _lastAutoConnectAt;
  List<_DiscoveredPc> _discoveredPcs = const [];
  List<_PcRequestFile> _requestFiles = const [];

  bool get _isTrusted =>
      _deviceId.isNotEmpty && _deviceToken.isNotEmpty && _pcId.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _speech = stt.SpeechToText();
    _prefs.setMethodCallHandler(_handleNativeCall);
    unawaited(_requestMicrophonePermission());
    _bootstrap();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    WidgetsBinding.instance.removeObserver(this);
    _speech.stop();
    _prefs.invokeMethod('stopAudioReceiver');
    _controlSocket?.destroy();
    _screenSocket?.destroy();
    _baseUrlController.dispose();
    _pairingTokenController.dispose();
    _urlController.dispose();
    _clipboardController.dispose();
    _liveTextController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final bottomInset = WidgetsBinding
        .instance.platformDispatcher.views.first.viewInsets.bottom;

    if (_lastBottomInset > 0.0 && bottomInset == 0.0) {
      FocusManager.instance.primaryFocus?.unfocus();
      _liveTextController.clear();
      _lastLiveText = '';
    }
    _lastBottomInset = bottomInset;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      unawaited(_autoConnectToTrustedPc());
    }
  }

  Future<void> _requestMicrophonePermission() async {
    final status = await Permission.microphone.status;
    if (!status.isGranted) {
      await Permission.microphone.request();
    }
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'nativeStatus') {
      if (mounted) {
        setState(() =>
            _status = call.arguments?.toString() ?? 'Native action finished');
      }
    } else if (call.method == 'deepLink') {
      await _handleDeepLink(call.arguments?.toString());
    }
    return null;
  }

  Future<void> _bootstrap() async {
    await _loadConfig();
    _ensureDeviceId();
    final link = await _prefs.invokeMethod<String>('consumeInitialDeepLink');
    await _handleDeepLink(link);
    unawaited(_autoConnectToTrustedPc(forceDiscovery: true));
  }

  Future<void> _handleDeepLink(String? link) async {
    if (link == null || link.isEmpty) return;
    final uri = Uri.tryParse(link);
    final scheme = uri?.scheme;
    if ((scheme != 'smartmpc' && scheme != 'nfcinstant') ||
        uri?.host != 'tap') {
      return;
    }

    if (uri?.queryParameters['action'] == 'request_files') {
      await _setTabIndex(_actionsTab);
      await _loadRequestFiles();
    }
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
        _quickAction = _validQuickAction(config['quickAction']?.toString());
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
      'quickAction': _quickAction,
    });
    if (showStatus && mounted) setState(() => _status = 'Config saved');
  }

  Future<void> _clearTrust() async {
    await _run('Clearing trust', () async {
      _disconnectRemote();
      setState(() {
        _deviceToken = '';
        _pcId = '';
      });
      await _saveConfig();
      return 'Phone trust cleared locally';
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

  Future<void> _discoverPcs() async {
    await _run('Searching local network', () async {
      final pcs = await _scanForPcs();
      setState(() => _discoveredPcs = pcs);

      if (pcs.isNotEmpty) {
        _applyDiscoveredPc(_bestDiscoveredPc(pcs) ?? pcs.first);
        await _saveConfig();
      }

      return pcs.isEmpty ? 'No PC found' : 'Found ${pcs.length} PC server(s)';
    });
  }

  Future<List<_DiscoveredPc>> _scanForPcs() async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    socket.broadcastEnabled = true;

    final results = <String, _DiscoveredPc>{};
    late StreamSubscription<RawSocketEvent> subscription;
    subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = socket.receive()) != null) {
        final discovered = _DiscoveredPc.tryParse(datagram!);
        if (discovered != null) {
          final previous = results[discovered.host];
          if (previous == null ||
              previous.pcId.isEmpty && discovered.pcId.isNotEmpty ||
              previous.name == previous.host &&
                  discovered.name != discovered.host) {
            results[discovered.host] = discovered;
          }
        }
      }
    });

    try {
      final targets = await _discoveryTargets();
      for (var round = 0; round < 4; round += 1) {
        for (final target in targets) {
          for (final message in const [
            'DISCOVER_SMART_MPC',
            'DISCOVER_MOBILEPC',
          ]) {
            socket.send(utf8.encode(message), target, 8081);
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      await Future<void>.delayed(const Duration(seconds: 1));
      final pcs = results.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      return pcs;
    } finally {
      await subscription.cancel();
      socket.close();
    }
  }

  Future<void> _autoConnectToTrustedPc({bool forceDiscovery = false}) async {
    if (!_isTrusted || _autoConnectInFlight) return;

    final now = DateTime.now();
    final lastAutoConnectAt = _lastAutoConnectAt;
    if (!forceDiscovery &&
        lastAutoConnectAt != null &&
        now.difference(lastAutoConnectAt) < const Duration(seconds: 8)) {
      return;
    }

    _autoConnectInFlight = true;
    _lastAutoConnectAt = now;

    try {
      if (mounted) {
        setState(() => _status = 'Finding trusted PC');
      }

      var addressChanged = false;
      try {
        final pcs = await _scanForPcs();
        if (!mounted) return;

        setState(() => _discoveredPcs = pcs);
        final pc = _bestDiscoveredPc(pcs);
        if (pc != null) {
          final previousBaseUrl = _normalizedBaseUrl();
          setState(() => _applyDiscoveredPc(pc));
          addressChanged = previousBaseUrl != _normalizedBaseUrl();
          if (addressChanged) {
            await _saveConfig();
          }
        }
      } catch (error) {
        if (mounted) {
          setState(() => _status = 'Auto discovery unavailable');
        }
      }

      if (addressChanged && _remoteConnected) {
        _controlSocket?.destroy();
        _controlSocket = null;
        if (mounted) {
          setState(() {
            _remoteConnected = false;
            _remoteStatus = 'Remote address updated';
          });
        }
      }

      if (!_remoteConnected) {
        await _connectRemote(auto: true);
      }
      if (mounted) {
        setState(() {
          _status = _remoteConnected
              ? 'Trusted PC connected'
              : 'Trusted PC not reachable';
        });
      }
    } finally {
      _autoConnectInFlight = false;
    }
  }

  _DiscoveredPc? _bestDiscoveredPc(List<_DiscoveredPc> pcs) {
    if (pcs.isEmpty) return null;

    if (_pcId.isNotEmpty) {
      for (final pc in pcs) {
        if (pc.pcId == _pcId) return pc;
      }
    }

    final currentHost = Uri.tryParse(_normalizedBaseUrl())?.host ?? '';
    if (currentHost.isNotEmpty) {
      for (final pc in pcs) {
        if (pc.host == currentHost ||
            Uri.tryParse(pc.baseUrl)?.host == currentHost) {
          return pc;
        }
      }
    }

    return pcs.first;
  }

  void _applyDiscoveredPc(_DiscoveredPc pc) {
    _baseUrlController.text = pc.baseUrl;
    _pcName = pc.name;
    if (pc.pcId.isNotEmpty) _pcId = pc.pcId;
  }

  Future<List<InternetAddress>> _discoveryTargets() async {
    final values = <String>{'255.255.255.255'};
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final parts = address.address.split('.');
        if (parts.length == 4) {
          values.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
        }
      }
    }
    return values.map(InternetAddress.new).toList();
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
      final url = _urlController.text.trim();
      if (url.isEmpty) throw Exception('URL is empty');
      await _postJson('/api/intent', {
        'type': 'url',
        'source': 'android',
        'payload': {'url': url},
      });
      return 'URL sent to PC';
    });
  }

  Future<void> _setQuickAction(String? value) async {
    setState(() => _quickAction = _validQuickAction(value));
    await _saveConfig(showStatus: true);
  }

  Future<void> _runTapAction() async {
    await _prefs.invokeMethod('runTapAction');
    setState(() => _status = 'Running tap action');
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
    setState(() => _status = 'Choose file(s) to send');
    await _prefs.invokeMethod('pickAndUploadFiles', {
      'baseUrl': _normalizedBaseUrl(),
      'deviceId': _deviceId,
      'deviceToken': _deviceToken,
    });
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
      setState(() => _status = 'Starting download: ${file.name}');
      final url =
          '${_normalizedBaseUrl()}/api/request-files/download?filename=${Uri.encodeQueryComponent(file.name)}';
      await _prefs.invokeMethod('downloadToDownloads', {
        'url': url,
        'filename': file.name,
        'deviceId': _deviceId,
        'deviceToken': _deviceToken,
      });
      return 'Download queued: ${file.name}';
    });
  }

  Future<void> _connectRemote({bool auto = false}) async {
    if (_remoteConnected && _controlSocket != null) return;

    if (!_isTrusted) {
      setState(() => _remoteStatus = 'Trust this phone first');
      return;
    }

    final uri = Uri.tryParse(_normalizedBaseUrl());
    final host = uri?.host ?? '';
    if (host.isEmpty) {
      setState(() => _remoteStatus = 'PC address is invalid');
      return;
    }

    setState(() =>
        _remoteStatus = auto ? 'Auto connecting remote' : 'Connecting remote');
    try {
      final socket =
          await Socket.connect(host, 8080, timeout: const Duration(seconds: 5));
      socket.setOption(SocketOption.tcpNoDelay, true);
      socket.listen(
        (_) {},
        onDone: () {
          if (mounted) {
            setState(() {
              _remoteConnected = false;
              _remoteStatus = 'Remote disconnected';
            });
          }
        },
        onError: (Object error) {
          if (mounted) {
            setState(() {
              _remoteConnected = false;
              _remoteStatus = 'Remote error: $error';
            });
          }
        },
        cancelOnError: true,
      );

      _controlSocket?.destroy();
      _controlSocket = socket;
      _sendRawControl({
        'type': 'auth',
        'device_id': _deviceId,
        'device_token': _deviceToken,
      });
      setState(() {
        _remoteConnected = true;
        _remoteStatus = 'Remote connected';
        if (auto) _status = 'Trusted PC connected';
      });
    } catch (error) {
      setState(() {
        _remoteConnected = false;
        _remoteStatus = auto
            ? 'Auto remote connect pending'
            : 'Remote connect failed: $error';
      });
    }
  }

  void _disconnectRemote() {
    if (_mirrorConnected) {
      _disconnectMirror();
    }
    if (_audioEnabled) {
      _sendRawControl({
        'type': 'AUDIO_TOGGLE',
        'enabled': false,
        'port': _audioPort,
      });
      _prefs.invokeMethod('stopAudioReceiver');
    }
    _controlSocket?.destroy();
    _controlSocket = null;
    setState(() {
      _remoteConnected = false;
      _audioEnabled = false;
      _remoteStatus = 'Remote disconnected';
      _audioStatus = 'PC audio off';
    });
  }

  void _sendRemoteCommand(Map<String, Object?> command) {
    if (!_remoteConnected || _controlSocket == null) {
      setState(() => _remoteStatus = 'Connect remote first');
      return;
    }
    _sendRawControl(command);
  }

  void _sendRawControl(Map<String, Object?> message) {
    _controlSocket?.write('${jsonEncode(message)}\n');
  }

  void _onTrackpadPointerDown(PointerDownEvent event) {
    _pointerPositions[event.pointer] = event.localPosition;
    _pointerStartPositions[event.pointer] = event.localPosition;
    if (_pointerPositions.length == 1) {
      _pointerDownTime = DateTime.now();
      _peakPointerCount = 1;
    }
    if (_pointerPositions.length > _peakPointerCount) {
      _peakPointerCount = _pointerPositions.length;
    }
  }

  void _onTrackpadPointerMove(PointerMoveEvent event) {
    _pointerPositions[event.pointer] = event.localPosition;

    if (_pointerPositions.length == 1) {
      _accumulatedDx += event.delta.dx;
      _accumulatedDy += event.delta.dy;
      final now = DateTime.now();
      if (now.difference(_lastMoveTime).inMilliseconds >= 16) {
        const sensitivity = 4.0;
        _sendRemoteCommand({
          'type': 'MOUSE_MOVE',
          'dx': _accumulatedDx * sensitivity,
          'dy': _accumulatedDy * sensitivity,
        });
        _lastMoveTime = now;
        _accumulatedDx = 0;
        _accumulatedDy = 0;
      }
    } else if (_pointerPositions.length >= 2) {
      final now = DateTime.now();
      if (now.difference(_lastMoveTime).inMilliseconds >= 16) {
        final dy = event.delta.dy;
        if (dy.abs() > 0.3) {
          _sendRemoteCommand({'type': 'SCROLL', 'dy': -dy * 0.5});
        }
        _lastMoveTime = now;
      }
    }
  }

  void _onTrackpadPointerUp(PointerUpEvent event) {
    final startPos = _pointerStartPositions[event.pointer];
    final endPos = event.localPosition;
    final duration = DateTime.now().difference(_pointerDownTime).inMilliseconds;

    if (_peakPointerCount == 1 && startPos != null) {
      final dx = endPos.dx - startPos.dx;
      final dy = endPos.dy - startPos.dy;
      final dist = dx * dx + dy * dy;
      if (dist < 400 && duration < 350) {
        _sendRemoteCommand({'type': 'MOUSE_CLICK', 'button': 'left'});
      }
    } else if (_peakPointerCount >= 2) {
      var avgDx = 0.0;
      var avgDy = 0.0;
      var count = 0;
      for (final id in _pointerStartPositions.keys) {
        final start = _pointerStartPositions[id];
        final current =
            _pointerPositions[id] ?? (id == event.pointer ? endPos : null);
        if (start != null && current != null) {
          avgDx += current.dx - start.dx;
          avgDy += current.dy - start.dy;
          count += 1;
        }
      }
      if (count > 0) {
        avgDx /= count;
        avgDy /= count;
      }
      final dist = avgDx * avgDx + avgDy * avgDy;

      if (dist < 500 && duration < 400) {
        _sendRemoteCommand({'type': 'MOUSE_CLICK', 'button': 'right'});
      } else if (dist >= 500 && avgDx.abs() > avgDy.abs()) {
        _sendRemoteCommand({
          'type': 'SPECIAL_KEY',
          'key': avgDx > 0 ? 'browserback' : 'browserforward',
        });
      }
    }

    _pointerPositions.remove(event.pointer);
    _pointerStartPositions.remove(event.pointer);
    if (_pointerPositions.isEmpty) {
      _peakPointerCount = 0;
    }
  }

  void _onLiveTextChanged(String value) {
    if (value == _lastLiveText) return;

    var commonLen = 0;
    final minLen = value.length < _lastLiveText.length
        ? value.length
        : _lastLiveText.length;
    while (commonLen < minLen && value[commonLen] == _lastLiveText[commonLen]) {
      commonLen += 1;
    }

    final backspacesNeeded = _lastLiveText.length - commonLen;
    for (var i = 0; i < backspacesNeeded; i += 1) {
      _sendRemoteCommand({'type': 'SPECIAL_KEY', 'key': 'backspace'});
    }

    final added = value.substring(commonLen);
    if (added.isNotEmpty) {
      _sendRemoteCommand({
        'type': 'TYPE_TEXT',
        'text': added,
      });
    }

    _lastLiveText = value;
  }

  Future<void> _startVoiceUi() async {
    if (!_remoteConnected) {
      setState(() => _remoteStatus = 'Connect remote first');
      return;
    }
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) {
            setState(() => _voiceListening = false);
          }
        }
      },
      onError: (error) => debugPrint('Speech error: $error'),
    );

    if (!available) {
      setState(() => _remoteStatus = 'Voice unavailable');
      return;
    }

    setState(() {
      _voiceListening = true;
      _lastRecognizedWords = '';
      _remoteStatus = 'Voice dictation listening';
    });
    await _speech.listen(
      onResult: (result) {
        final recognizedWords = result.recognizedWords;
        if (recognizedWords.startsWith(_lastRecognizedWords)) {
          final newWords =
              recognizedWords.substring(_lastRecognizedWords.length);
          if (newWords.isNotEmpty) {
            _sendRemoteCommand({'type': 'TYPE_TEXT', 'text': newWords});
          }
        }
        _lastRecognizedWords = recognizedWords;
      },
      listenOptions:
          stt.SpeechListenOptions(listenMode: stt.ListenMode.dictation),
    );
  }

  void _stopVoiceUi() {
    _speech.stop();
    setState(() {
      _voiceListening = false;
      _remoteStatus =
          _remoteConnected ? 'Remote connected' : 'Remote disconnected';
    });
  }

  Future<void> _toggleAudio() async {
    if (_audioEnabled) {
      await _stopAudio();
    } else {
      await _startAudio();
    }
  }

  Future<void> _startAudio() async {
    if (!_remoteConnected || _controlSocket == null) {
      setState(() => _audioStatus = 'Connect remote first');
      return;
    }
    try {
      await _prefs.invokeMethod('startAudioReceiver', {'port': _audioPort});
      _sendRemoteCommand({
        'type': 'AUDIO_TOGGLE',
        'enabled': true,
        'port': _audioPort,
      });
      setState(() {
        _audioEnabled = true;
        _audioStatus = 'PC audio on';
      });
    } catch (error) {
      setState(() => _audioStatus = 'Audio failed: $error');
    }
  }

  Future<void> _stopAudio() async {
    if (_remoteConnected && _controlSocket != null) {
      _sendRemoteCommand({
        'type': 'AUDIO_TOGGLE',
        'enabled': false,
        'port': _audioPort,
      });
    }
    await _prefs.invokeMethod('stopAudioReceiver');
    setState(() {
      _audioEnabled = false;
      _audioStatus = 'PC audio off';
    });
  }

  Future<void> _connectMirror() async {
    if (!_isTrusted) {
      setState(() => _mirrorStatus = 'Trust this phone first');
      return;
    }
    if (!_remoteConnected) {
      await _connectRemote();
    }
    if (!_remoteConnected) {
      setState(() => _mirrorStatus = 'Remote control is required');
      return;
    }

    final uri = Uri.tryParse(_normalizedBaseUrl());
    final host = uri?.host ?? '';
    if (host.isEmpty) {
      setState(() => _mirrorStatus = 'PC address is invalid');
      return;
    }

    setState(() => _mirrorStatus = 'Connecting mirror');
    try {
      final socket =
          await Socket.connect(host, 8082, timeout: const Duration(seconds: 5));
      socket.setOption(SocketOption.tcpNoDelay, true);
      _screenSocket?.destroy();
      _screenSocket = socket;
      _screenBuffer = [];
      _screenFrame = null;
      _screenHandshakeDone = false;
      socket.listen(
        _handleScreenData,
        onDone: _markMirrorDisconnected,
        onError: (Object error) {
          if (mounted) {
            setState(() {
              _mirrorConnected = false;
              _mirrorStatus = 'Mirror error: $error';
            });
          }
        },
        cancelOnError: true,
      );
      socket.write('${jsonEncode({
            'type': 'auth',
            'device_id': _deviceId,
            'device_token': _deviceToken,
          })}\n');
      setState(() {
        _mirrorConnected = true;
        _mirrorStatus = 'Mirror connected';
      });
    } catch (error) {
      setState(() {
        _mirrorConnected = false;
        _mirrorStatus = 'Mirror connect failed: $error';
      });
    }
  }

  void _disconnectMirror() {
    _screenSocket?.destroy();
    _screenSocket = null;
    _screenBuffer = [];
    _screenFrame = null;
    _screenHandshakeDone = false;
    setState(() {
      _mirrorConnected = false;
      _mirrorStatus = 'Mirror disconnected';
    });
  }

  void _markMirrorDisconnected() {
    if (!mounted) return;
    setState(() {
      _mirrorConnected = false;
      _mirrorStatus = 'Mirror disconnected';
    });
  }

  void _handleScreenData(Uint8List chunk) {
    _screenBuffer.addAll(chunk);

    if (!_screenHandshakeDone) {
      final newline = _screenBuffer.indexOf(10);
      if (newline < 0) return;

      final line = utf8.decode(_screenBuffer.sublist(0, newline));
      _screenBuffer = _screenBuffer.sublist(newline + 1);
      final message = jsonDecode(line) as Map<String, dynamic>;
      if (message['ok'] == false) {
        setState(() =>
            _mirrorStatus = message['error']?.toString() ?? 'Mirror denied');
        _disconnectMirror();
        return;
      }
      _screenHandshakeDone = true;
    }

    while (_screenBuffer.length >= 4) {
      final length = (_screenBuffer[0] << 24) |
          (_screenBuffer[1] << 16) |
          (_screenBuffer[2] << 8) |
          _screenBuffer[3];
      if (length <= 0 || length > 5 * 1024 * 1024) {
        setState(() => _mirrorStatus = 'Invalid screen frame');
        _disconnectMirror();
        return;
      }
      if (_screenBuffer.length < length + 4) return;

      final frame = Uint8List.fromList(_screenBuffer.sublist(4, length + 4));
      _screenBuffer = _screenBuffer.sublist(length + 4);
      if (mounted) {
        setState(() {
          _screenFrame = frame;
          _mirrorStatus = 'Mirror receiving';
        });
      }
    }
  }

  void _sendMirrorTouch(
    String type,
    Offset position,
    BoxConstraints constraints,
  ) {
    if (!_remoteConnected) {
      setState(() => _mirrorStatus = 'Connect mirror control first');
      return;
    }
    final width = constraints.maxWidth <= 0 ? 1.0 : constraints.maxWidth;
    final height = constraints.maxHeight <= 0 ? 1.0 : constraints.maxHeight;
    final rx = (position.dx / width).clamp(0.0, 1.0);
    final ry = (position.dy / height).clamp(0.0, 1.0);
    _sendRemoteCommand({
      'type': type,
      'rx': rx,
      'ry': ry,
    });
  }

  void _sendMirrorTouchUp() {
    if (!_remoteConnected) {
      setState(() => _mirrorStatus = 'Connect mirror control first');
      return;
    }
    _sendRemoteCommand({'type': 'TOUCH_UP'});
  }

  void _handleMirrorPointerDown(
    PointerDownEvent event,
    BoxConstraints constraints,
  ) {
    _mirrorActivePointers.add(event.pointer);
    if (_mirrorActivePointers.length == 1) {
      _sendMirrorTouch('TOUCH_DOWN', event.localPosition, constraints);
    } else if (_mirrorActivePointers.length == 2) {
      _sendMirrorTouchUp();
    }
  }

  void _handleMirrorPointerMove(
    PointerMoveEvent event,
    BoxConstraints constraints,
  ) {
    if (_mirrorActivePointers.length != 1) return;
    final now = DateTime.now();
    if (now.difference(_lastMirrorMoveTime).inMilliseconds < 16) return;
    _sendMirrorTouch('TOUCH_MOVE', event.localPosition, constraints);
    _lastMirrorMoveTime = now;
  }

  void _handleMirrorPointerUp(PointerEvent event) {
    _mirrorActivePointers.remove(event.pointer);
    if (_mirrorActivePointers.isEmpty) {
      _sendMirrorTouchUp();
    }
  }

  Future<void> _setTabIndex(int index) async {
    if (index < _actionsTab || index > _connectTab) return;

    if (index == _remoteTab) {
      unawaited(_autoConnectToTrustedPc());
    }

    if (index == _mirrorTab) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeRight,
        DeviceOrientation.landscapeLeft,
      ]);
      setState(() => _tabIndex = index);
      if (!_mirrorConnected) {
        unawaited(_connectMirror());
      }
      return;
    }

    if (_tabIndex == _mirrorTab) {
      _mirrorActivePointers.clear();
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
    setState(() => _tabIndex = index);
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

  String _validQuickAction(String? value) {
    const ids = {
      'send_file',
      'pull_clipboard',
      'request_files',
      'open_chrome',
      'lock_pc',
      'sleep_pc',
    };
    return ids.contains(value) ? value! : 'send_file';
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildActionsPage(),
      _buildRemotePage(),
      _buildMirrorPage(),
      _buildConnectPage(),
    ];
    final isMirrorTab = _tabIndex == _mirrorTab;
    final isRemoteTab = _tabIndex == _remoteTab;
    final isImmersiveTab = isRemoteTab || isMirrorTab;

    return Scaffold(
      resizeToAvoidBottomInset: !isImmersiveTab,
      backgroundColor: isMirrorTab ? Colors.black : null,
      appBar: isImmersiveTab
          ? null
          : AppBar(
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
      body: isMirrorTab ? pages[_tabIndex] : SafeArea(child: pages[_tabIndex]),
      bottomNavigationBar: isImmersiveTab
          ? null
          : NavigationBar(
              selectedIndex: _tabIndex,
              onDestinationSelected: (index) => unawaited(_setTabIndex(index)),
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.bolt_rounded), label: 'Actions'),
                NavigationDestination(
                    icon: Icon(Icons.touch_app_rounded), label: 'Remote'),
                NavigationDestination(
                    icon: Icon(Icons.screenshot_monitor_rounded),
                    label: 'Mirror'),
                NavigationDestination(
                    icon: Icon(Icons.lan_rounded), label: 'Connect'),
              ],
            ),
    );
  }

  Future<void> _exitMirrorPage() async {
    _mirrorActivePointers.clear();
    _disconnectMirror();
    await _setTabIndex(_actionsTab);
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
                    onPressed: _busy ? null : _discoverPcs,
                    icon: const Icon(Icons.radar_rounded),
                    label: const Text('Find PC'),
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
        if (_discoveredPcs.isNotEmpty) ...[
          const SizedBox(height: 14),
          _SectionCard(
            title: 'Discovered PCs',
            child: Column(
              children: _discoveredPcs
                  .map(
                    (pc) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.desktop_windows_rounded),
                      title: Text(pc.name),
                      subtitle: Text(pc.baseUrl),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () {
                        setState(() => _applyDiscoveredPc(pc));
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
          title: 'Tap Action',
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: _quickAction,
                decoration: const InputDecoration(
                  labelText: 'Quick Action',
                  prefixIcon: Icon(Icons.nfc_rounded),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'send_file', child: Text('Send file')),
                  DropdownMenuItem(
                      value: 'pull_clipboard',
                      child: Text('Pull PC clipboard')),
                  DropdownMenuItem(
                      value: 'request_files', child: Text('Request PC files')),
                  DropdownMenuItem(
                      value: 'open_chrome', child: Text('Open Chrome')),
                  DropdownMenuItem(value: 'lock_pc', child: Text('Lock PC')),
                  DropdownMenuItem(value: 'sleep_pc', child: Text('Sleep PC')),
                ],
                onChanged: _busy ? null : _setQuickAction,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _runTapAction,
                  icon: const Icon(Icons.touch_app_rounded),
                  label: const Text('Run Tap Action'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
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

  Widget _buildRemotePage() {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            Row(
              children: [
                Tooltip(
                  message: 'Back to Actions',
                  child: IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => unawaited(_setTabIndex(_actionsTab)),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                ),
                const Spacer(),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (_remoteConnected)
                      Tooltip(
                        message: _audioEnabled
                            ? 'Turn PC audio off'
                            : 'Turn PC audio on',
                        child: IconButton.filledTonal(
                          visualDensity: VisualDensity.compact,
                          onPressed: _toggleAudio,
                          icon: Icon(
                            _audioEnabled
                                ? Icons.speaker_group_rounded
                                : Icons.volume_off_rounded,
                            color: _audioEnabled
                                ? const Color(0xFF64FFDA)
                                : Colors.redAccent,
                          ),
                        ),
                      ),
                    Icon(
                      _remoteConnected ? Icons.wifi : Icons.wifi_off,
                      color: _remoteConnected
                          ? Colors.greenAccent
                          : Colors.redAccent,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _remoteStatus,
                    style: TextStyle(
                      color: _remoteConnected
                          ? Colors.greenAccent
                          : Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                  if (_remoteConnected)
                    Text(
                      _audioStatus,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _liveTextController,
              decoration: _remoteInputDecoration(
                'Live Type to PC...',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey, size: 20),
                  onPressed: () {
                    _liveTextController.clear();
                    _lastLiveText = '';
                    FocusManager.instance.primaryFocus?.unfocus();
                  },
                ),
              ),
              style: const TextStyle(color: Colors.white),
              textInputAction: TextInputAction.send,
              onChanged: _onLiveTextChanged,
              onSubmitted: (_) => _sendRemoteCommand({
                'type': 'SPECIAL_KEY',
                'key': 'enter',
              }),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _remoteSpecialKeyButton(
                      'Alt+Tab', Icons.compare_arrows_rounded, 'alttab'),
                  _remoteSpecialKeyButton(
                      'Enter', Icons.keyboard_return_rounded, 'enter'),
                  _remoteSpecialKeyButton(
                      'Bksp', Icons.backspace_rounded, 'backspace'),
                  _remoteSpecialKeyButton(
                      'Refresh', Icons.refresh_rounded, 'f5'),
                  _remoteSpecialKeyButton(
                      'Copy', Icons.content_copy_rounded, 'copy'),
                  _remoteSpecialKeyButton(
                      'Paste', Icons.content_paste_rounded, 'paste'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onLongPressStart: (_) => _startVoiceUi(),
              onLongPressEnd: (_) => _stopVoiceUi(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: _voiceListening
                      ? Colors.redAccent.withValues(alpha: 0.9)
                      : const Color(0xFF1A1D2D),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _voiceListening
                        ? Colors.redAccent
                        : Colors.teal.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                  boxShadow: _voiceListening
                      ? [
                          BoxShadow(
                            color: Colors.redAccent.withValues(alpha: 0.4),
                            blurRadius: 15,
                          )
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.mic_rounded,
                      size: 40,
                      color: _voiceListening
                          ? Colors.white
                          : const Color(0xFF64FFDA),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _voiceListening
                          ? 'Listening... (Release to Stop)'
                          : 'Hold for Voice Command',
                      style: TextStyle(
                        color: _voiceListening ? Colors.white : Colors.white70,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Listener(
                onPointerDown: _onTrackpadPointerDown,
                onPointerMove: _onTrackpadPointerMove,
                onPointerUp: _onTrackpadPointerUp,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF131520),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.teal.withValues(alpha: 0.15),
                    ),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.touch_app_rounded,
                          color: Colors.white24,
                          size: 48,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'TOUCHPAD',
                          style: TextStyle(
                            color: Colors.white30,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Tap - 2-Finger Tap - 2-Finger Swipe',
                          style: TextStyle(
                            color: Colors.white24,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  InputDecoration _remoteInputDecoration(String label, {Widget? suffixIcon}) {
    return InputDecoration(
      suffixIcon: suffixIcon,
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey),
      filled: true,
      fillColor: const Color(0xFF1A1D2D),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF64FFDA), width: 1.5),
      ),
    );
  }

  Widget _remoteSpecialKeyButton(String label, IconData icon, String keyId) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        height: 54,
        width: 76,
        child: ElevatedButton(
          onPressed: () => _sendRemoteCommand({
            'type': 'SPECIAL_KEY',
            'key': keyId,
          }),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.all(4),
            backgroundColor: const Color(0xFF1A1D2D),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            side: BorderSide(
              color: Colors.teal.withValues(alpha: 0.3),
            ),
            elevation: 2,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: const Color(0xFF64FFDA)),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMirrorPage() {
    return Stack(
      children: [
        Center(
          child: _screenFrame == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFFEF4444)),
                    const SizedBox(height: 16),
                    Text(
                      _mirrorStatus,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                )
              : AspectRatio(
                  aspectRatio: 16 / 9,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return InteractiveViewer(
                        panEnabled: false,
                        minScale: 1,
                        maxScale: 5,
                        child: Listener(
                          onPointerDown: (event) =>
                              _handleMirrorPointerDown(event, constraints),
                          onPointerMove: (event) =>
                              _handleMirrorPointerMove(event, constraints),
                          onPointerUp: _handleMirrorPointerUp,
                          onPointerCancel: _handleMirrorPointerUp,
                          child: Container(
                            width: double.infinity,
                            height: double.infinity,
                            color: Colors.black,
                            child: Image.memory(
                              _screenFrame!,
                              gaplessPlayback: true,
                              fit: BoxFit.fill,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
        Positioned(
          top: 20,
          left: 20,
          child: SafeArea(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => unawaited(_exitMirrorPage()),
              ),
            ),
          ),
        ),
        Positioned(
          top: 20,
          right: 20,
          child: SafeArea(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.54),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _mirrorConnected
                          ? Icons.screenshot_monitor_rounded
                          : Icons.sync_problem_rounded,
                      color: _mirrorConnected
                          ? const Color(0xFF65D6A6)
                          : const Color(0xFFFCA5A5),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _mirrorConnected ? 'Mirror' : _mirrorStatus,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed:
                          _mirrorConnected ? _disconnectMirror : _connectMirror,
                      icon: Icon(
                        _mirrorConnected
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DiscoveredPc {
  const _DiscoveredPc({
    required this.name,
    required this.baseUrl,
    required this.pcId,
    required this.host,
  });

  final String name;
  final String baseUrl;
  final String pcId;
  final String host;

  static _DiscoveredPc? tryParse(Datagram datagram) {
    final text = utf8.decode(datagram.data, allowMalformed: true).trim();
    if (text.isEmpty) return null;

    final payload = _decodePayload(text);
    if (payload == null) return null;

    final type = payload['type']?.toString() ?? '';
    if (type != 'SMART_MPC_SERVER' && type != 'MOBILEPC_SERVER') return null;

    final baseUrls = (payload['base_urls'] as List<dynamic>? ?? [])
        .map((value) => value.toString())
        .where((value) => value.startsWith('http://'))
        .toList();
    final port = int.tryParse(payload['port']?.toString() ?? '') ?? 8765;
    final fallbackUrl = 'http://${datagram.address.address}:$port';
    final matchingUrl = _matchingBaseUrl(baseUrls, datagram.address.address);
    final baseUrl =
        matchingUrl ?? (baseUrls.isEmpty ? fallbackUrl : baseUrls.first);
    final pcName = payload['pc_name']?.toString().trim() ?? '';

    return _DiscoveredPc(
      name: pcName.isEmpty ? datagram.address.address : pcName,
      baseUrl: baseUrl,
      pcId: payload['pc_id']?.toString() ?? '',
      host: datagram.address.address,
    );
  }

  static Map<String, dynamic>? _decodePayload(String text) {
    try {
      if (text.startsWith('{')) {
        return jsonDecode(text) as Map<String, dynamic>;
      }
      if (text.startsWith('MOBILEPC_SERVER') ||
          text.startsWith('SMART_MPC_SERVER')) {
        final jsonStart = text.indexOf('{');
        if (jsonStart >= 0) {
          return jsonDecode(text.substring(jsonStart)) as Map<String, dynamic>;
        }
        return {
          'type': text.startsWith('SMART_MPC_SERVER')
              ? 'SMART_MPC_SERVER'
              : 'MOBILEPC_SERVER',
        };
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static String? _matchingBaseUrl(List<String> urls, String host) {
    for (final url in urls) {
      if (Uri.tryParse(url)?.host == host) return url;
    }
    return null;
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
                  color: colors.primary.withValues(alpha: 0.12),
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
        border: Border.all(color: color.withValues(alpha: 0.7)),
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
