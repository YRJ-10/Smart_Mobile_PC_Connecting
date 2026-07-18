import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'media_state.dart';
import 'webrtc_video_renderer.dart';

class WebRtcMirrorView extends StatelessWidget {
  const WebRtcMirrorView({
    super.key,
    required this.renderer,
    required this.renderState,
    required this.mediaState,
    required this.onExit,
    required this.onRetry,
  });

  final RTCVideoRenderer renderer;
  final WebRtcVideoRenderState renderState;
  final MediaState mediaState;
  final VoidCallback onExit;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final waiting =
        renderState.phase == WebRtcVideoRenderPhase.waitingForFrame ||
            mediaState.videoPhase == MediaTrackPhase.starting;
    final failed = renderState.phase == WebRtcVideoRenderPhase.failed ||
        mediaState.videoPhase == MediaTrackPhase.failed;

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (renderState.phase == WebRtcVideoRenderPhase.waitingForFrame ||
              renderState.phase == WebRtcVideoRenderPhase.rendering)
            RTCVideoView(
              renderer,
              mirror: false,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
              filterQuality: FilterQuality.low,
            ),
          if (waiting && !renderState.hasFrame)
            const _MirrorMessage(
              icon: CircularProgressIndicator(
                color: Color(0xFFEF4444),
                strokeWidth: 3,
              ),
              label: 'Connecting mirror',
            ),
          if (failed)
            _MirrorFailure(
              message: renderState.error ??
                  mediaState.error ??
                  'Mirror connection failed',
              onRetry: onRetry,
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
                child: Tooltip(
                  message: 'Back',
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: onExit,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 20,
            right: 20,
            child: SafeArea(
              child: _MirrorStatus(
                connected: renderState.hasFrame,
                width: renderState.width,
                height: renderState.height,
              ),
            ),
          ),
        ],
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
  const _MirrorFailure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

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
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
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
