# PC Worker

Modul ini akan berisi worker Python untuk fitur yang perlu akses langsung ke OS Windows.

Tanggung jawab:

- Mouse move.
- Left/right click.
- Scroll.
- Keyboard typing.
- Special keys.
- Browser gestures.
- Zoom.
- Media play/pause.
- PC audio loopback capture.
- Audio stream ke Android.
- Screen capture.
- Screen frame encoding.
- Touch coordinate execution dari screen mirror.

Sumber referensi read-only:

- prototype media remote Python server implementation

Catatan:

- Worker tidak menjadi security authority utama.
- Worker menerima command yang sudah divalidasi oleh `pc_app`.
- Detail transport final akan mengikuti `shared_protocol`.

## Fase 7: Remote Control Worker

Dependency awal:

```powershell
pip install -r requirements.txt
```

Command yang dijalankan:

- mouse move
- mouse click
- scroll
- type text
- special key
- zoom
- media play/pause
- touch down/move/up
- PC audio loopback capture
- UDP PCM audio stream
- screen capture
- JPEG frame encoding
