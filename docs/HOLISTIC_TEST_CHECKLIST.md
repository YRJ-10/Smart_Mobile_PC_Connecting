# Holistic Test Checklist

Gunakan checklist ini setelah semua fase integrasi selesai.

## Persiapan PC

- Install dependency PC app.
- Install dependency worker Python dari `pc_worker/requirements.txt`.
- Jalankan PC app.
- Pastikan HTTP, Remote, Discovery, dan Mirror status running di desktop shell.
- Catat pairing token dari desktop shell.
- Pastikan firewall mengizinkan jaringan lokal untuk port `8765`, `8080`, `8081`, dan `8082`.

## Persiapan Android

- Jalankan Android app.
- Tekan Find PC.
- Pilih PC yang ditemukan atau isi address manual.
- Tekan Health.
- Masukkan pairing token.
- Tekan Trust Phone.

## Test Connection dan Auth

- Health berhasil.
- Pair Info berhasil.
- Trusted indicator aktif.
- Device muncul di desktop shell.
- Revoke device memutus akses lama.

## Test File dan Clipboard

- Send File dari Android ke PC inbox.
- Add Files dari PC shell ke outbox.
- Request Files dari Android.
- Download file PC ke Android Downloads.
- Send clipboard Android ke PC.
- Pull clipboard PC ke Android.

## Test Quick Actions dan NFC

- Run Tap Action untuk setiap quick action.
- NFC/deep link membuka action.
- Open Chrome.
- Lock PC.
- Sleep PC jika aman untuk diuji.

## Test Remote Control

- Connect Remote.
- Trackpad menggerakkan mouse.
- Left/right click.
- Scroll.
- Live typing.
- Backspace handling.
- Alt+Tab, Enter, Refresh, Copy, Paste.
- Browser back/forward.
- Zoom.
- Media play/pause.

## Test Audio

- Tekan PC Audio.
- Audio PC terdengar di Android.
- Stop Audio berhenti bersih.
- Remote command tetap responsif saat audio aktif.

## Test Mirror

- Connect Mirror.
- Frame layar PC muncul.
- Pinch/zoom viewer bekerja.
- Touch down/move/up mempengaruhi PC.
- Disconnect Mirror berhenti bersih.

## Catatan Hasil

- Catat fitur yang gagal.
- Catat pesan error dari Android.
- Catat activity log PC shell.
- Catat apakah masalah terjadi di Wi-Fi, firewall, dependency worker, atau mapping input.
