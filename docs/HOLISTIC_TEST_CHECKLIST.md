# Holistic Test Checklist

Gunakan checklist ini untuk uji lengkap setelah semua fase repair selesai. Jalankan dengan sabar dari atas ke bawah agar jika ada kegagalan, titik gagalnya jelas.

## Persiapan Runtime

- Jalankan `scripts/prepare_runtime.cmd` jika dependency belum pernah disiapkan setelah perubahan terakhir.
- Jalankan `scripts/start_pc_app.cmd` untuk membuka desktop shell PC.
- Pastikan server HTTP, remote control, dan discovery berjalan di desktop shell.
- Pastikan Windows Firewall mengizinkan PC Server dan koneksi jaringan lokal.
- Sebelum media dinyalakan, pastikan tidak ada media worker atau screen-streamer
  yang memakai CPU di Task Manager.
- Catat pairing token dari desktop shell.

## Persiapan Android

- Jalankan Android app dari Android Studio.
- Buka tab Connect.
- Tekan Find PC.
- Pastikan PC Address terisi otomatis jika PC ditemukan.
- Jika Find PC gagal, isi PC Address manual.
- Masukkan pairing token.
- Tekan Trust Phone.
- Tekan Save.
- Tutup dan buka ulang app Android, lalu pastikan PC Address dan token masih tersimpan.

## Connect Tab

- Device ID muncul.
- Trusted indicator aktif setelah Trust Phone.
- Clear Local Trust menghapus trust lokal.
- Discovered PCs muncul setelah Find PC berhasil.
- Mengetuk item Discovered PCs mengisi PC Address.
- Tidak ada section Health, Pair Info, atau PC Addresses.

## Actions Tab

- Send File mengirim file Android ke inbox PC.
- PC shell Add Files memasukkan file ke outbox.
- Request Files menampilkan daftar outbox di Android.
- Tombol download tiap file menyimpan file ke Downloads Android.
- Send Clipboard mengirim teks Android ke clipboard PC.
- Pull Clipboard mengambil clipboard PC ke Android.
- Open URL membuka URL di PC.
- Command Open Chrome bekerja.
- Lock PC bekerja jika aman diuji.
- Sleep PC hanya diuji jika memang aman.

## NFC Quick Actions

- Tap action `send_file` membuka picker lalu upload ke PC.
- Tap action `pull_clipboard` mengambil clipboard PC.
- Tap action `request_files` membuka app ke flow request files.
- Tap action `open_chrome` menjalankan command PC.
- Tap action `lock_pc` menjalankan lock jika aman.
- Tap action `sleep_pc` hanya diuji jika aman.
- Deep link `smartmpc://tap` masih diproses.
- Legacy scheme `nfcinstant://tap` masih diproses.

## Remote Tab

- Connect Remote berhasil.
- Trackpad satu jari menggerakkan mouse dengan sensitivitas yang terasa seperti project acuan.
- Tap satu jari menjadi left click.
- Tap dua jari menjadi right click.
- Scroll dua jari berjalan.
- Swipe horizontal dua jari menjadi browser back/forward.
- Live typing mengirim teks.
- Edit tengah teks mengirim backspace dan teks baru dengan benar.
- Tombol Alt+Tab, Enter, Backspace, Refresh, Copy, dan Paste bekerja.
- Voice dictation mengirim teks ke PC.

## Audio

- Tekan Audio ON.
- Audio musik dan dialog PC terdengar jernih di Android.
- Tidak ada mute burst, fadeout berulang, atau efek suara terkompresi seperti
  panggilan telepon.
- Delay awal tetap rendah dan tidak terus menumpuk setelah beberapa menit.
- Remote control tetap responsif saat audio aktif.
- Pindah ke Actions dan Remote; ikon audio global tetap tersedia.
- Kunci layar; audio tetap berjalan dan media control tampil di lock screen.
- Uji pause/stop dari notification atau lock screen.
- Buka app kembali; kontrol audio tetap sesuai state stream.
- Putuskan socket Remote sementara; audio WebRTC tidak ikut mati.
- Tekan Audio OFF.
- Audio dan notification berhenti bersih.
- Pastikan wake lock, Wi-Fi lock, dan media session tidak tertinggal setelah stop.

## Mirror

- Buka tab Mirror.
- Android masuk landscape.
- Mirror auto-connect.
- Frame layar PC muncul tanpa crop pada native aspect ratio.
- Uji desktop statis, gerakan jendela cepat, grafik bergerak, dan pemutaran video.
- Gerak cepat tidak membuat stream membeku; kualitas boleh beradaptasi sementara
  mengikuti congestion control.
- Cursor PC terlihat sebagai bagian dari screen capture.
- Mirror bersifat view-only; sentuhan tidak mengontrol PC.
- Pindahkan app ke background lalu kembali; mirror berhenti di background dan
  tersambung kembali saat tab terlihat.
- Tombol back overlay keluar dari mirror dan kembali portrait.
- Tombol back kembali ke tab Actions.
- Keluar dari mirror menghentikan capture dan video worker dengan bersih.

## Resource Lifecycle

- Dengan audio dan mirror OFF, media worker PC tidak berjalan.
- Audio ON hanya mengaktifkan audio capture; mirror OFF tidak mengaktifkan video.
- Mirror ON hanya mengaktifkan video capture bila audio OFF.
- Audio dan mirror bersamaan berbagi satu media worker/session pipeline.
- Ulangi start/stop audio dan masuk/keluar mirror minimal tiga kali.
- Setelah session terakhir berhenti, tidak ada orphan Electron media worker,
  screen-streamer, audio worker, notification, atau Android media service.
- Trackpad dan NFC tetap bekerja setelah seluruh siklus media selesai.

## Discovery

- Find PC menemukan PC lewat UDP.
- Legacy request `DISCOVER_MOBILEPC` tetap dijawab.
- Smart request `DISCOVER_SMART_MPC` tetap dijawab.
- Jika PC ditemukan lewat legacy response lebih dulu, metadata JSON tetap memperbarui hasil saat datang.

## Catatan Hasil

- Catat fitur yang gagal.
- Catat langkah terakhir sebelum gagal.
- Catat pesan status Android.
- Catat activity log PC shell.
- Catat apakah kegagalan terkait firewall, dependency worker, pairing/trust, atau input mapping.
