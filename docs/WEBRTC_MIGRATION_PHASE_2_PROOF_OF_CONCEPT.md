# WebRTC Migration Phase 2 Proof of Concept

Tanggal: 2026-07-17

## Keputusan Stack

PC menggunakan WebRTC yang sudah tersedia di Chromium milik Electron. Android
menggunakan `flutter_webrtc` versi `1.5.2`.

Alasan:

- Electron sudah memiliki `RTCPeerConnection`, Opus, dan video codecs sehingga PC
  tidak memerlukan WebRTC framework kedua;
- Electron mendukung desktop capture serta system-audio loopback pada Windows;
- `flutter_webrtc` menggunakan Google WebRTC dan mendukung Android audio/video,
  data channel, Unified Plan, dan renderer native;
- dependency Android berlisensi MIT;
- kedua sisi dapat bekerja peer-to-peer di LAN tanpa STUN/TURN server.

## PC Probe

Probe terisolasi tersedia melalui:

```text
npm run check:webrtc
```

Probe membuat dua peer connection tersembunyi di renderer sandbox, menggunakan
`iceServers: []`, membuka data channel, mengirim payload, menerima echo, lalu
menutup kedua peer.

Hasil aktual:

- Electron: `42.5.2`;
- Chromium: `148.0.7778.271`;
- data channel loopback: berhasil;
- host candidates tanpa STUN/TURN: berhasil;
- Opus: tersedia;
- VP8: tersedia;
- H.264: tersedia;
- AV1 dan VP9 juga dilaporkan runtime, tetapi bukan codec target awal.

Probe hanya berjalan saat command eksplisit dipanggil. PC Server startup tidak
menjalankannya.

## Android Probe

Dependency dikunci secara eksplisit:

```text
flutter_webrtc: 1.5.2
```

`WebRtcProbe.run()` membuat dua native peer connection tanpa ICE server, membuka
data channel, melakukan offer/answer, memverifikasi echo payload, dan selalu
menutup channel serta peer dalam `finally`.

Probe belum dihubungkan ke startup atau UI. Pemanggilan runtime pada perangkat
akan dilakukan setelah signaling/foundation memiliki lifecycle yang benar.

Izin Android yang ditambahkan hanya:

- access network state;
- change network state;
- modify audio settings.

Permission kamera tidak ditambahkan karena Android hanya menjadi receiver untuk
screen mirror. Permission microphone yang sudah ada tetap dimiliki voice typing.

## Verifikasi

- Node/Electron syntax check: lulus.
- Electron WebRTC runtime/data-channel probe: lulus.
- Flutter Analyze: lulus tanpa issue.
- Android debug APK dengan native WebRTC: berhasil dibangun.
- Ukuran debug APK universal: sekitar 174 MiB; angka ini bukan ukuran release dan
  belum menggunakan ABI split.
- Tidak ada Electron probe process yang tertinggal setelah pemeriksaan.
- APK release `2.2.2` yang terpasang pada pengguna tidak dibangun atau ditimpa.

## Dampak Runtime

Belum ada dampak runtime production:

- aplikasi tidak menginisialisasi peer connection;
- PC Server tidak memulai capture atau encoder;
- Android tidak membuka renderer, audio track, atau media service WebRTC;
- seluruh fitur lama tetap memakai engine legacy.

## Batas Fase 2

Fase ini membuktikan compatibility stack dan local peer primitives. Fase ini belum
mengirim media PC ke Android. Signaling trusted-device dibuat pada Fase 3, media
worker lifecycle pada Fase 4, dan Android peer foundation pada Fase 5.
