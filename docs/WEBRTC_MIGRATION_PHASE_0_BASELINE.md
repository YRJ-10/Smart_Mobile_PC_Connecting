# WebRTC Migration Phase 0 Baseline

Tanggal baseline: 2026-07-17

## Titik Stabil

- Release Android: `2.2.2+5`.
- Commit stabil: `4827b78`.
- Tag rollback: `v2.2.2-baseline`.
- Branch stabil: `master`.
- Branch migrasi: `codex/webrtc-migration`.

Commit dan tag tersebut adalah sumber kebenaran jika migrasi media menyebabkan
regresi. Migrasi tidak boleh mengubah baseline secara langsung.

## Tujuan Migrasi

Hanya mesin media realtime yang diganti:

- audio PCM/UDP lama menjadi audio WebRTC dengan Opus;
- screen mirror JPEG/TCP lama menjadi video WebRTC;
- signaling tetap lokal melalui PC Server;
- tidak ada cloud, TURN berbayar, akun, atau koneksi media ke internet.

## Fitur Yang Dikunci

Fitur berikut tidak boleh dirombak selama migrasi media:

- pairing token, trust phone, device token, dan penyimpanan konfigurasi;
- auto-connect, discovery, manual PC address, dan status koneksi;
- NFC quick actions dan deep link `smartmpc://tap` serta `nfcinstant://tap`;
- upload file, progress transfer, request/download file, inbox, dan outbox;
- send/pull clipboard dan open URL;
- PC commands Chrome, lock, sleep, dan monitor profiles;
- trackpad satu jari, sensitivitas, akselerasi, dan interval low-latency 8 ms;
- left click, right click, middle click, drag hold, dan two-finger scroll;
- browser back/forward gesture;
- live typing, Enter, arrow keys, special keys, dan voice typing;
- tab order, immersive remote layout, dan struktur UI yang sudah diterima;
- PC tray app, pairing UI, activity list, dan opsi run at startup.

Jika file yang memuat fitur terkunci harus disentuh, perubahan wajib kecil,
terlokalisasi, dan tidak boleh mengubah perilakunya.

## Kontrak Media Baru

- WebRTC ditambahkan berdampingan dengan mesin lama melalui feature flag.
- Audio dan video boleh berbagi satu peer connection, tetapi track media memiliki
  lifecycle terpisah.
- Capture, encoder, decoder, dan media worker hanya hidup ketika fiturnya `ON`.
- Audio `OFF` tidak boleh menjalankan audio capture atau encoder.
- Mirror `OFF` tidak boleh menjalankan screen capture atau video encoder.
- Saat semua media `OFF`, hanya server lokal ringan dan control channel yang boleh
  tetap hidup.
- Menutup stream wajib menghentikan seluruh process tree maksimal dua detik.
- Tidak boleh ada orphan `screen-streamer`, audio worker, atau WebRTC worker.
- Kegagalan media tidak boleh memutus trackpad atau control channel.
- Android harus melepaskan renderer, track, receiver, dan foreground service saat
  media berhenti.

## Baseline Transport Lama

Transport lama dipertahankan sementara sebagai fallback:

- HTTP API: port `8765`;
- realtime control TCP: port `8080`;
- audio PCM UDP: port `8081`;
- screen JPEG TCP: port `8082`.

Transport lama baru boleh dihapus setelah audio dan video WebRTC lulus acceptance
gate. UI lama tidak menjadi alasan untuk mempertahankan implementasi transport
lama.

## Masalah Media Yang Sudah Terbukti

- Audio PCM 16 kHz mono mengalami dropout/fadeout dan kualitas buruk pada musik
  atau suara kompleks.
- Penyetelan buffer lama tidak menghasilkan kualitas production yang stabil.
- JPEG frame-per-frame membeku ketika perubahan layar cepat atau video tampil.
- `smart-mpc-screen-streamer.exe` dapat tertinggal sebagai orphan setelah mirror
  ditutup dan tetap memakai CPU tanpa klien aktif.

Masalah tersebut adalah alasan migrasi arsitektur, bukan alasan mengubah fitur
lain yang sudah berhasil.

## Acceptance Gate

Migrasi dianggap berhasil hanya jika:

- audio musik dan dialog berjalan tanpa mute burst atau fadeout berulang;
- startup audio tetap low-latency dan tidak terus menumpuk delay;
- media notification dan lock-screen controls hanya tampil saat audio aktif;
- mirror tetap responsif pada desktop statis, pergerakan cepat, grafik, dan video;
- tidak ada media worker saat audio dan mirror `OFF`;
- memulai dan menghentikan media berulang kali tidak meninggalkan proses;
- trackpad tetap memiliki feel dan presisi release `2.2.2`;
- NFC, file, clipboard, commands, pairing, dan discovery tetap berfungsi;
- APK dan PC Server dapat dibangun sebagai paket production portabel.

## Jalur Rollback

Jika fase migrasi menyebabkan regresi yang tidak dapat diterima, hentikan build
migrasi dan gunakan kembali commit/tag `v2.2.2-baseline`. Jangan memperbaiki
regresi dengan mengubah baseline stabil.
