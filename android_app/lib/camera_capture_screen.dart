import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

const _panelBorder = Color(0xFF344248);
const _accentSoft = Color(0xFF8EDFD1);
const _successSoft = Color(0xFF8FDCAD);
const _dangerSoft = Color(0xFFD87A7A);
const _mutedText = Color(0xFF9AA8AF);

class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({
    super.key,
    required this.cameras,
    required this.onMediaCaptured,
  });

  final List<CameraDescription> cameras;
  final Future<void> Function(File file, String filename) onMediaCaptured;

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  CameraController? _controller;
  int _selectedCameraIndex = 0;
  bool _isCameraInitialized = false;
  bool _isVideoMode = false;
  bool _isRecording = false;
  int _recordingDuration = 0;
  Timer? _recordingTimer;
  XFile? _capturedFile;
  bool _isCapturedVideo = false;
  bool _isUploading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initCamera(_selectedCameraIndex);
  }

  Future<void> _initCamera(int index) async {
    if (widget.cameras.isEmpty) return;
    setState(() {
      _isCameraInitialized = false;
      _errorMessage = null;
    });

    final previous = _controller;
    _controller = CameraController(
      widget.cameras[index],
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await previous?.dispose();

    try {
      await _controller!.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
          _selectedCameraIndex = index;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Gagal inisialisasi kamera: $e');
      }
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _toggleCamera() async {
    if (widget.cameras.length < 2 || _isRecording) return;
    final nextIndex = (_selectedCameraIndex + 1) % widget.cameras.length;
    await _initCamera(nextIndex);
  }

  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized || _isRecording) return;

    try {
      final file = await _controller!.takePicture();
      if (mounted) {
        setState(() {
          _capturedFile = file;
          _isCapturedVideo = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengambil foto: $e'), backgroundColor: _dangerSoft),
        );
      }
    }
  }

  Future<void> _startRecording() async {
    if (_controller == null || !_controller!.value.isInitialized || _isRecording) return;

    try {
      await _controller!.startVideoRecording();
      _recordingDuration = 0;
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() => _recordingDuration++);
        }
      });
      setState(() => _isRecording = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal merekam video: $e'), backgroundColor: _dangerSoft),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    if (_controller == null || !_isRecording) return;

    try {
      _recordingTimer?.cancel();
      final file = await _controller!.stopVideoRecording();
      if (mounted) {
        setState(() {
          _isRecording = false;
          _capturedFile = file;
          _isCapturedVideo = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRecording = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghentikan rekaman: $e'), backgroundColor: _dangerSoft),
        );
      }
    }
  }

  void _retake() {
    if (_isUploading) return;
    setState(() {
      _capturedFile = null;
      _isCapturedVideo = false;
    });
  }

  Future<void> _confirmAndSend() async {
    if (_capturedFile == null || _isUploading) return;
    setState(() => _isUploading = true);

    final now = DateTime.now();
    final d = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final t = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final ext = _isCapturedVideo ? 'mp4' : 'jpg';
    final prefix = _isCapturedVideo ? 'video' : 'photo';
    final filename = '${prefix}_${d}_$t.$ext';

    try {
      await widget.onMediaCaptured(File(_capturedFile!.path), filename);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengirim media: $e'), backgroundColor: _dangerSoft),
        );
      }
    }
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _capturedFile != null ? _buildPreviewUi() : _buildCameraUi(),
      ),
    );
  }

  Widget _buildPreviewUi() {
    return Stack(
      children: [
        Center(
          child: _isCapturedVideo
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_rounded, size: 80, color: _accentSoft),
                    const SizedBox(height: 16),
                    Text(
                      'Video Siap Dikirim (${_formatDuration(_recordingDuration)})',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Video tersimpan dan siap ditransfer langsung ke PC.',
                      style: TextStyle(color: _mutedText, fontSize: 13),
                    ),
                  ],
                )
              : Image.file(
                  File(_capturedFile!.path),
                  fit: BoxFit.contain,
                ),
        ),
        Positioned(
          top: 16,
          left: 16,
          child: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
            onPressed: _isUploading ? null : () => Navigator.of(context).pop(),
          ),
        ),
        Positioned(
          bottom: 24,
          left: 20,
          right: 20,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OutlinedButton.icon(
                onPressed: _isUploading ? null : _retake,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Ulangi'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: _panelBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                ),
              ),
              FilledButton.icon(
                onPressed: _isUploading ? null : _confirmAndSend,
                icon: _isUploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.send_rounded, color: Colors.black),
                label: Text(
                  _isUploading ? 'Mengirim...' : 'Kirim ke PC',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: _successSoft,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCameraUi() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: _dangerSoft, size: 48),
              const SizedBox(height: 16),
              Text(_errorMessage!, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _initCamera(_selectedCameraIndex),
                child: const Text('Coba Lagi'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isCameraInitialized || _controller == null) {
      return const Center(child: CircularProgressIndicator(color: _accentSoft));
    }

    return Stack(
      children: [
        Positioned.fill(
          child: CameraPreview(_controller!),
        ),
        Positioned(
          top: 16,
          left: 16,
          child: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        if (widget.cameras.length > 1)
          Positioned(
            top: 16,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.flip_camera_android_rounded, color: Colors.white, size: 28),
              onPressed: _isRecording ? null : _toggleCamera,
            ),
          ),
        if (_isRecording)
          Positioned(
            top: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.fiber_manual_record, color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      _formatDuration(_recordingDuration),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isRecording) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text('FOTO'),
                      selected: !_isVideoMode,
                      onSelected: (val) {
                        if (val) setState(() => _isVideoMode = false);
                      },
                      selectedColor: _accentSoft,
                      labelStyle: TextStyle(
                        color: !_isVideoMode ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 12),
                    ChoiceChip(
                      label: const Text('VIDEO'),
                      selected: _isVideoMode,
                      onSelected: (val) {
                        if (val) setState(() => _isVideoMode = true);
                      },
                      selectedColor: _accentSoft,
                      labelStyle: TextStyle(
                        color: _isVideoMode ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              GestureDetector(
                onTap: _isVideoMode
                    ? (_isRecording ? _stopRecording : _startRecording)
                    : _takePhoto,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _isVideoMode
                          ? (_isRecording ? Colors.red : Colors.redAccent)
                          : Colors.white,
                      borderRadius: _isRecording && _isVideoMode
                          ? BorderRadius.circular(8)
                          : BorderRadius.circular(40),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
