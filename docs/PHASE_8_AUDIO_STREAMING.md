# Phase 8 - Audio Streaming

Tujuan fase ini adalah mengaktifkan streaming audio PC ke Android tanpa mengubah project referensi dan tanpa menghapus fitur fase sebelumnya.

Yang ditambahkan:

- Command `AUDIO_TOGGLE` dari Android ke PC lewat TCP control channel yang sudah trusted.
- PC control server menyisipkan target IP Android dari socket authenticated.
- Python worker menangkap audio PC dan mengirim PCM lewat UDP.
- Android native UDP receiver memakai `AudioTrack` untuk playback low-latency.
- Tombol PC Audio di tab Remote Android.

Format audio awal:

- Transport: UDP.
- Port receiver Android: `8081`.
- Encoding: PCM signed 16-bit little-endian.
- Sample rate: `16000`.
- Channel: mono.

Catatan implementasi:

- Worker memakai `soundcard` dan `numpy` untuk audio capture.
- Di Windows, worker memakai loopback microphone dari default speaker seperti implementasi referensi.
- Jika loopback tidak tersedia di runtime, worker akan melaporkan error lewat activity log.
- Audio tetap dikendalikan oleh trusted control channel; UDP hanya menerima stream setelah Android menyalakan receiver.

Belum dikerjakan di fase ini:

- UI device picker audio output.
- Adaptive jitter buffer.
- Codec kompresi.
- Full latency tuning.
- Full integration test lintas device.
