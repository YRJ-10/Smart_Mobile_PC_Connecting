# Repair Phase 10 - Audio Parity

Status: complete.

Tujuan fase ini adalah mengembalikan jalur audio agar lebih dekat ke implementasi media remote yang sudah terbukti.

## Yang Dipulihkan

- Android native audio receiver memakai `AudioTrack.Builder`.
- Playback memakai `USAGE_MEDIA`, `CONTENT_TYPE_MUSIC`, PCM 16-bit mono, sample rate `16000`.
- Buffer Android kembali ke `AudioTrack.getMinBufferSize(...)` dengan UDP receive buffer `minBufferSize * 2`.
- `AudioTrack` memakai `MODE_STREAM` dan `PERFORMANCE_MODE_LOW_LATENCY`.
- UDP receiver tetap memakai port `8081`.
- PC worker audio capture kembali memakai `soundcard` loopback seperti referensi.
- Worker memilih default speaker, mencari loopback microphone yang namanya cocok, lalu fallback ke microphone pertama jika perlu.
- Audio frame PC kembali ke `256` frames per packet.
- Payload UDP tetap PCM signed 16-bit little-endian mono.

## File Yang Berubah

- `android_app/android/app/src/main/kotlin/com/smartmpc/app/MainActivity.kt`
- `pc_worker/worker.py`
- `pc_worker/requirements.txt`
- `docs/PHASE_8_AUDIO_STREAMING.md`
- `docs/REPAIR_PHASE_1_REFERENCE_MAPPING.md`

## Catatan

- Fase ini sengaja mengganti worker dari `sounddevice` ke `soundcard` karena implementasi referensi yang berhasil memakai `soundcard`.
- Kontrak command tidak berubah: Android tetap mengirim `AUDIO_TOGGLE`, PC server tetap menyisipkan target host Android, worker tetap mengirim stream UDP ke Android.
- Start order tetap Android receiver lebih dulu, lalu command `AUDIO_TOGGLE enabled=true` dikirim ke PC.

## Verifikasi

- `gradlew :app:compileDebugKotlin`
- `python -m py_compile pc_worker/worker.py` memakai interpreter lokal yang tersedia
