import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'media_state.dart';
import 'webrtc_video_renderer.dart';

class WebRtcMirrorView extends StatefulWidget {
  const WebRtcMirrorView({
    super.key,
    required this.renderer,
    required this.renderState,
    required this.mediaState,
    required this.onExit,
    required this.onRetry,
    this.onRestartServer,
    this.onSendCommand,
  });

  final RTCVideoRenderer renderer;
  final WebRtcVideoRenderState renderState;
  final MediaState mediaState;
  final VoidCallback onExit;
  final VoidCallback onRetry;
  final VoidCallback? onRestartServer;
  final void Function(Map<String, Object?> command)? onSendCommand;

  @override
  State<WebRtcMirrorView> createState() => _WebRtcMirrorViewState();
}

class _WebRtcMirrorViewState extends State<WebRtcMirrorView> {
  bool _touchControlEnabled = true;

  final Map<int, Offset> _pointerPositions = {};
  final Map<int, Offset> _pointerStartPositions = {};
  int _peakPointerCount = 0;
  DateTime _lastMoveTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isDragging = false;
  bool _isRightClickTriggered = false;
  Timer? _longPressTimer;

  Offset? _touchRipplePosition;
  double _touchRippleOpacity = 0.0;
  Timer? _rippleFadeTimer;

  bool _keyboardOpen = false;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _keyboardFocusNode = FocusNode();
  String _lastTypedText = '';

  double _scale = 1.0;
  Offset _panOffset = Offset.zero;
  double _initialPinchDistance = 0.0;
  double _initialScale = 1.0;
  Offset _initialPinchMidpoint = Offset.zero;
  Offset _initialPanOffset = Offset.zero;
  bool _isPinchGesture = false;
  DateTime? _lastTapTime;
  Offset? _lastTapPosition;

  static const int _moveIntervalMillis = 16;
  static const double _dragThreshold = 8.0;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _rippleFadeTimer?.cancel();
    _textController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _onLiveTextChanged(String value) {
    if (value == _lastTypedText) return;

    var commonLen = 0;
    final minLen = value.length < _lastTypedText.length
        ? value.length
        : _lastTypedText.length;
    while (commonLen < minLen && value[commonLen] == _lastTypedText[commonLen]) {
      commonLen += 1;
    }

    final backspacesNeeded = _lastTypedText.length - commonLen;
    for (var i = 0; i < backspacesNeeded; i += 1) {
      widget.onSendCommand?.call({'type': 'SPECIAL_KEY', 'key': 'backspace'});
    }

    final added = value.substring(commonLen);
    if (added.isNotEmpty) {
      widget.onSendCommand?.call({
        'type': 'TYPE_TEXT',
        'text': added,
      });
    }

    _lastTypedText = value;
  }

  void _sendSpecialKey(String key) {
    widget.onSendCommand?.call({'type': 'SPECIAL_KEY', 'key': key});
  }

  void _toggleKeyboard() {
    setState(() {
      _keyboardOpen = !_keyboardOpen;
      if (_keyboardOpen) {
        _lastTypedText = '';
        _textController.clear();
        _keyboardFocusNode.requestFocus();
      } else {
        _keyboardFocusNode.unfocus();
        _textController.clear();
        _lastTypedText = '';
      }
    });
  }

  Offset? _normalizeCoordinates(Offset localPosition, BoxConstraints constraints) {
    final videoWidth = widget.renderState.width;
    final videoHeight = widget.renderState.height;
    final containerWidth = constraints.maxWidth;
    final containerHeight = constraints.maxHeight;

    if (videoWidth <= 0 || videoHeight <= 0 || containerWidth <= 0 || containerHeight <= 0) {
      return null;
    }

    final videoAspectRatio = videoWidth / videoHeight;
    final containerAspectRatio = containerWidth / containerHeight;

    double displayedWidth;
    double displayedHeight;
    double offsetX = 0.0;
    double offsetY = 0.0;

    if (containerAspectRatio > videoAspectRatio) {
      // Container is wider than video (pillarbox)
      displayedHeight = containerHeight;
      displayedWidth = containerHeight * videoAspectRatio;
      offsetX = (containerWidth - displayedWidth) / 2.0;
    } else {
      // Container is taller than video (letterbox)
      displayedWidth = containerWidth;
      displayedHeight = containerWidth / videoAspectRatio;
      offsetY = (containerHeight - displayedHeight) / 2.0;
    }

    final containerCenter = Offset(containerWidth / 2.0, containerHeight / 2.0);
    final untransformedPosition = _scale > 1.001
        ? (localPosition - containerCenter - _panOffset) / _scale + containerCenter
        : localPosition;

    final relX = untransformedPosition.dx - offsetX;
    final relY = untransformedPosition.dy - offsetY;

    // Check if within bounds of displayed video area
    if (relX < -12.0 || relX > displayedWidth + 12.0 || relY < -12.0 || relY > displayedHeight + 12.0) {
      return null;
    }

    final rx = (relX / displayedWidth).clamp(0.0, 1.0);
    final ry = (relY / displayedHeight).clamp(0.0, 1.0);

    return Offset(rx, ry);
  }

  void _triggerVisualRipple(Offset position) {
    _rippleFadeTimer?.cancel();
    setState(() {
      _touchRipplePosition = position;
      _touchRippleOpacity = 1.0;
    });
    _rippleFadeTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted) {
        setState(() => _touchRippleOpacity = 0.0);
      }
    });
  }

  void _onPointerDown(PointerDownEvent event, BoxConstraints constraints) {
    if (!_touchControlEnabled || !widget.renderState.hasFrame || widget.onSendCommand == null) {
      return;
    }

    final norm = _normalizeCoordinates(event.localPosition, constraints);
    if (norm == null) return;

    _pointerPositions[event.pointer] = event.localPosition;
    _pointerStartPositions[event.pointer] = event.localPosition;
    _peakPointerCount = _pointerPositions.length;

    if (_pointerPositions.length == 1) {
      _isDragging = false;
      _isRightClickTriggered = false;
      _triggerVisualRipple(event.localPosition);

      // Start long-press timer for right-click
      _longPressTimer?.cancel();
      _longPressTimer = Timer(const Duration(milliseconds: 550), () {
        if (!mounted) return;
        if (_pointerPositions.length == 1 && !_isDragging && !_isRightClickTriggered && !_isPinchGesture) {
          _isRightClickTriggered = true;
          HapticFeedback.mediumImpact();
          widget.onSendCommand?.call({'type': 'TOUCH_MOVE', 'rx': norm.dx, 'ry': norm.dy});
          widget.onSendCommand?.call({'type': 'MOUSE_CLICK', 'button': 'right'});
        }
      });
    } else if (_pointerPositions.length >= 2) {
      _longPressTimer?.cancel();
      final points = _pointerPositions.values.toList();
      _initialPinchDistance = (points[0] - points[1]).distance;
      _initialScale = _scale;
      _initialPinchMidpoint = (points[0] + points[1]) / 2.0;
      _initialPanOffset = _panOffset;
      _isPinchGesture = false;
    }
  }

  void _onPointerMove(PointerMoveEvent event, BoxConstraints constraints) {
    if (!_touchControlEnabled || !widget.renderState.hasFrame || widget.onSendCommand == null) {
      return;
    }

    if (!_pointerPositions.containsKey(event.pointer)) return;
    _pointerPositions[event.pointer] = event.localPosition;

    if (_pointerPositions.length == 1 && !_isRightClickTriggered && !_isPinchGesture) {
      final startPos = _pointerStartPositions[event.pointer];
      if (startPos != null) {
        final dist = (event.localPosition - startPos).distance;
        if (dist > _dragThreshold) {
          _longPressTimer?.cancel();
          if (!_isDragging) {
            _isDragging = true;
            final startNorm = _normalizeCoordinates(startPos, constraints);
            final currentNorm = _normalizeCoordinates(event.localPosition, constraints);
            if (startNorm != null) {
              // 1. Move exactly to initial touch spot where user pressed
              widget.onSendCommand?.call({'type': 'TOUCH_MOVE', 'rx': startNorm.dx, 'ry': startNorm.dy});
              // 2. Press left mouse button down at initial touch spot
              widget.onSendCommand?.call({'type': 'TOUCH_DOWN', 'rx': startNorm.dx, 'ry': startNorm.dy});
            }
            if (currentNorm != null) {
              // 3. Move cursor to current drag position
              widget.onSendCommand?.call({'type': 'TOUCH_MOVE', 'rx': currentNorm.dx, 'ry': currentNorm.dy});
            }
            _lastMoveTime = DateTime.now();
          }
        }
      }

      if (_isDragging) {
        final now = DateTime.now();
        if (now.difference(_lastMoveTime).inMilliseconds >= _moveIntervalMillis) {
          final norm = _normalizeCoordinates(event.localPosition, constraints);
          if (norm != null) {
            widget.onSendCommand?.call({'type': 'TOUCH_MOVE', 'rx': norm.dx, 'ry': norm.dy});
          }
          _lastMoveTime = now;
        }
      }
    } else if (_pointerPositions.length >= 2) {
      _longPressTimer?.cancel();
      final points = _pointerPositions.values.toList();
      final currentDistance = (points[0] - points[1]).distance;
      final currentMidpoint = (points[0] + points[1]) / 2.0;
      final deltaDistance = (currentDistance - _initialPinchDistance).abs();

      if (_isPinchGesture || deltaDistance > 14.0 || _scale > 1.05) {
        if (!_isPinchGesture && deltaDistance > 14.0) {
          _isPinchGesture = true;
        }

        final containerWidth = constraints.maxWidth;
        final containerHeight = constraints.maxHeight;

        double targetScale = _scale;
        if (_initialPinchDistance > 10.0) {
          targetScale = (_initialScale * (currentDistance / _initialPinchDistance)).clamp(1.0, 4.0);
        }

        final panDelta = currentMidpoint - _initialPinchMidpoint;
        final candidatePan = _initialPanOffset + panDelta;

        final maxPanX = (containerWidth * (targetScale - 1.0)) / 2.0;
        final maxPanY = (containerHeight * (targetScale - 1.0)) / 2.0;

        final clampedPan = targetScale <= 1.05
            ? Offset.zero
            : Offset(
                candidatePan.dx.clamp(-maxPanX, maxPanX),
                candidatePan.dy.clamp(-maxPanY, maxPanY),
              );

        setState(() {
          _scale = targetScale <= 1.05 ? 1.0 : targetScale;
          _panOffset = clampedPan;
        });
      } else {
        // Two-finger scroll on PC
        final now = DateTime.now();
        if (now.difference(_lastMoveTime).inMilliseconds >= _moveIntervalMillis) {
          final dy = event.delta.dy;
          if (dy.abs() > 0.3) {
            widget.onSendCommand?.call({'type': 'SCROLL', 'dy': -dy * 0.5});
          }
          _lastMoveTime = now;
        }
      }
    }
  }

  void _onPointerUp(PointerUpEvent event, BoxConstraints constraints) {
    _longPressTimer?.cancel();

    if (!_touchControlEnabled || !widget.renderState.hasFrame || widget.onSendCommand == null) {
      _cleanupPointer(event.pointer);
      return;
    }

    final startPos = _pointerStartPositions[event.pointer];
    final norm = _normalizeCoordinates(event.localPosition, constraints);

    if (_isRightClickTriggered) {
      // Handled by long-press
    } else if (_peakPointerCount >= 2 && startPos != null && !_isPinchGesture) {
      // Two-finger tap for right-click
      final dist = (event.localPosition - startPos).distance;
      if (dist < 20.0 && !_isDragging) {
        _isRightClickTriggered = true;
        HapticFeedback.mediumImpact();
        if (norm != null) {
          widget.onSendCommand?.call({'type': 'TOUCH_MOVE', 'rx': norm.dx, 'ry': norm.dy});
          widget.onSendCommand?.call({'type': 'MOUSE_CLICK', 'button': 'right'});
        }
      }
    } else if (_isDragging) {
      // Finish drag
      if (norm != null) {
        widget.onSendCommand?.call({'type': 'TOUCH_MOVE', 'rx': norm.dx, 'ry': norm.dy});
        widget.onSendCommand?.call({'type': 'TOUCH_UP', 'rx': norm.dx, 'ry': norm.dy});
      } else {
        widget.onSendCommand?.call({'type': 'TOUCH_UP'});
      }
    } else if (_peakPointerCount == 1 && startPos != null && norm != null && !_isPinchGesture) {
      // Single tap or double-tap
      final dist = (event.localPosition - startPos).distance;
      if (dist < _dragThreshold) {
        final now = DateTime.now();
        if (_lastTapTime != null &&
            now.difference(_lastTapTime!).inMilliseconds < 300 &&
            _lastTapPosition != null &&
            (event.localPosition - _lastTapPosition!).distance < 30.0) {
          // Double-tap zoom toggle
          _lastTapTime = null;
          _lastTapPosition = null;
          setState(() {
            if (_scale > 1.2) {
              _scale = 1.0;
              _panOffset = Offset.zero;
            } else {
              _scale = 2.0;
              final containerCenter = Offset(constraints.maxWidth / 2.0, constraints.maxHeight / 2.0);
              final focalOffset = containerCenter - event.localPosition;
              final maxPanX = (constraints.maxWidth * (_scale - 1.0)) / 2.0;
              final maxPanY = (constraints.maxHeight * (_scale - 1.0)) / 2.0;
              _panOffset = Offset(
                (focalOffset.dx * 1.0).clamp(-maxPanX, maxPanX),
                (focalOffset.dy * 1.0).clamp(-maxPanY, maxPanY),
              );
            }
          });
        } else {
          _lastTapTime = now;
          _lastTapPosition = event.localPosition;
          widget.onSendCommand?.call({'type': 'TOUCH_DOWN', 'rx': norm.dx, 'ry': norm.dy});
          widget.onSendCommand?.call({'type': 'TOUCH_UP', 'rx': norm.dx, 'ry': norm.dy});
        }
      }
    }

    _cleanupPointer(event.pointer);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _longPressTimer?.cancel();
    if (_isDragging) {
      widget.onSendCommand?.call({'type': 'TOUCH_UP'});
    }
    _cleanupPointer(event.pointer);
  }

  void _cleanupPointer(int pointer) {
    _pointerPositions.remove(pointer);
    _pointerStartPositions.remove(pointer);
    if (_pointerPositions.isEmpty) {
      _peakPointerCount = 0;
      _isDragging = false;
      _isRightClickTriggered = false;
      _isPinchGesture = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final waiting =
        widget.renderState.phase == WebRtcVideoRenderPhase.waitingForFrame ||
            widget.mediaState.videoPhase == MediaTrackPhase.starting;
    final failed = widget.renderState.phase == WebRtcVideoRenderPhase.failed ||
        widget.mediaState.videoPhase == MediaTrackPhase.failed;

    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            fit: StackFit.expand,
            children: [
              if (widget.renderState.phase == WebRtcVideoRenderPhase.waitingForFrame ||
                  widget.renderState.phase == WebRtcVideoRenderPhase.rendering)
                ClipRect(
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..translate(_panOffset.dx, _panOffset.dy)
                      ..scale(_scale),
                    child: RTCVideoView(
                      widget.renderer,
                      mirror: false,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                      filterQuality: FilterQuality.low,
                    ),
                  ),
                ),

              // Direct Touch Control Overlay
              if (widget.renderState.hasFrame)
                Positioned.fill(
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (e) => _onPointerDown(e, constraints),
                    onPointerMove: (e) => _onPointerMove(e, constraints),
                    onPointerUp: (e) => _onPointerUp(e, constraints),
                    onPointerCancel: _onPointerCancel,
                  ),
                ),

              // Visual Touch Feedback Ripple
              if (_touchRipplePosition != null && _touchControlEnabled)
                Positioned(
                  left: _touchRipplePosition!.dx - 18,
                  top: _touchRipplePosition!.dy - 18,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _touchRippleOpacity,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF8EDFD1).withValues(alpha: 0.22),
                          border: Border.all(
                            color: const Color(0xFF8EDFD1).withValues(alpha: 0.7),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              if (waiting && !widget.renderState.hasFrame)
                const _MirrorMessage(
                  icon: CircularProgressIndicator(
                    color: Color(0xFFEF4444),
                    strokeWidth: 3,
                  ),
                  label: 'Connecting mirror',
                ),

              if (failed)
                _MirrorFailure(
                  message: widget.renderState.error ??
                      widget.mediaState.error ??
                      'Mirror connection failed',
                  onRetry: widget.onRetry,
                  onRestartServer: widget.onRestartServer,
                ),

              // Top Left: Back Button
              Positioned(
                top: 20,
                left: 20,
                child: SafeArea(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Tooltip(
                      message: 'Back',
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: widget.onExit,
                      ),
                    ),
                  ),
                ),
              ),

              // Top Right: Touch Control Toggle + Mirror Status
              Positioned(
                top: 20,
                right: 20,
                child: SafeArea(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.renderState.hasFrame) ...[
                        if (_scale > 1.05) ...[
                          _ZoomReset(
                            scale: _scale,
                            onReset: () {
                              setState(() {
                                _scale = 1.0;
                                _panOffset = Offset.zero;
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                        _TouchToggle(
                          enabled: _touchControlEnabled,
                          onToggle: () {
                            setState(() => _touchControlEnabled = !_touchControlEnabled);
                          },
                        ),
                        const SizedBox(width: 8),
                        _KeyboardToggle(
                          enabled: _keyboardOpen,
                          onToggle: _toggleKeyboard,
                        ),
                        const SizedBox(width: 8),
                      ],
                      _MirrorStatus(
                        connected: widget.renderState.hasFrame,
                        width: widget.renderState.width,
                        height: widget.renderState.height,
                      ),
                    ],
                  ),
                ),
              ),

              if (_keyboardOpen && widget.renderState.hasFrame)
                _buildKeyboardPanel(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildKeyboardPanel(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Positioned(
      left: 12,
      right: 12,
      bottom: bottomInset > 0 ? bottomInset + 8 : 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xE61E293B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF38BDF8), width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _keyChip('Enter', Icons.keyboard_return_rounded, () => _sendSpecialKey('enter')),
                    _keyChip('Bksp', Icons.backspace_rounded, () => _sendSpecialKey('backspace')),
                    _keyChip('Alt+Tab', Icons.compare_arrows_rounded, () => _sendSpecialKey('alttab')),
                    _keyChip('Copy', Icons.content_copy_rounded, () => _sendSpecialKey('copy')),
                    _keyChip('Paste', Icons.content_paste_rounded, () => _sendSpecialKey('paste')),
                    _keyChip('Refresh', Icons.refresh_rounded, () => _sendSpecialKey('f5')),
                    _keyChip('←', Icons.arrow_back_rounded, () => _sendSpecialKey('left')),
                    _keyChip('→', Icons.arrow_forward_rounded, () => _sendSpecialKey('right')),
                    _keyChip('↑', Icons.arrow_upward_rounded, () => _sendSpecialKey('up')),
                    _keyChip('↓', Icons.arrow_downward_rounded, () => _sendSpecialKey('down')),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 42,
                      child: TextField(
                        controller: _textController,
                        focusNode: _keyboardFocusNode,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        textInputAction: TextInputAction.send,
                        decoration: InputDecoration(
                          hintText: 'Ketik teks ke PC...',
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF0F172A),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          suffixIcon: _textController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 16, color: Colors.white54),
                                  onPressed: () {
                                    _textController.clear();
                                    _lastTypedText = '';
                                    setState(() {});
                                  },
                                )
                              : null,
                        ),
                        onChanged: (val) {
                          _onLiveTextChanged(val);
                          setState(() {});
                        },
                        onSubmitted: (_) {
                          _sendSpecialKey('enter');
                          _textController.clear();
                          _lastTypedText = '';
                          setState(() {});
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Tutup Keyboard',
                    icon: const Icon(Icons.keyboard_hide_rounded, color: Colors.white70),
                    onPressed: _toggleKeyboard,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _keyChip(String label, IconData icon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF334155),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: const Color(0xFF38BDF8)),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeyboardToggle extends StatelessWidget {
  const _KeyboardToggle({
    required this.enabled,
    required this.onToggle,
  });

  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: enabled ? const Color(0xFF38BDF8) : Colors.white24,
          width: 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.keyboard_rounded,
                  color: enabled ? const Color(0xFF38BDF8) : Colors.white54,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  'Keyboard',
                  style: TextStyle(
                    color: enabled ? Colors.white : Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TouchToggle extends StatelessWidget {
  const _TouchToggle({
    required this.enabled,
    required this.onToggle,
  });

  final bool enabled;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: enabled ? const Color(0xFF86EFAC) : Colors.white24,
          width: 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  enabled ? Icons.touch_app_rounded : Icons.pan_tool_rounded,
                  color: enabled ? const Color(0xFF86EFAC) : Colors.white54,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  enabled ? 'Touch ON' : 'Touch OFF',
                  style: TextStyle(
                    color: enabled ? Colors.white : Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MirrorMessage extends StatelessWidget {
  const _MirrorMessage({required this.icon, required this.label});

  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(height: 14),
          Text(label, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _MirrorFailure extends StatelessWidget {
  const _MirrorFailure({
    required this.message,
    required this.onRetry,
    this.onRestartServer,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onRestartServer;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sync_problem_rounded,
                color: Color(0xFFFCA5A5), size: 34),
            const SizedBox(height: 12),
            Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onRestartServer != null) ...[
                  OutlinedButton.icon(
                    onPressed: onRestartServer,
                    icon: const Icon(Icons.restart_alt_rounded, size: 18),
                    label: const Text('Restart Server'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF8EDFD1),
                      side: const BorderSide(color: Color(0xFF344248), width: 1.2),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MirrorStatus extends StatelessWidget {
  const _MirrorStatus({
    required this.connected,
    required this.width,
    required this.height,
  });

  final bool connected;
  final int width;
  final int height;

  @override
  Widget build(BuildContext context) {
    final resolution = width > 0 && height > 0 ? ' $width x $height' : '';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.54),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              connected ? Icons.screenshot_monitor_rounded : Icons.sync_rounded,
              color:
                  connected ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5),
              size: 17,
            ),
            const SizedBox(width: 7),
            Text(
              connected ? 'Mirror$resolution' : 'Connecting',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomReset extends StatelessWidget {
  const _ZoomReset({
    required this.scale,
    required this.onReset,
  });

  final double scale;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE60284C7),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 8,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onReset,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.zoom_in_rounded, color: Colors.white, size: 16),
                const SizedBox(width: 4),
                Text(
                  '${scale.toStringAsFixed(1)}x',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.restart_alt_rounded, color: Colors.white70, size: 15),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
