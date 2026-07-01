# Phase 7 - Remote Control Live

Tujuan fase ini adalah mengaktifkan remote control realtime dari Android ke PC tanpa menghapus fitur fase sebelumnya.

Yang ditambahkan:

- TCP control channel di port `8080`.
- Auth awal channel control memakai trusted device id dan token.
- Node control server yang berjalan bersama server utama.
- Python worker untuk eksekusi mouse, keyboard, scroll, zoom, media, dan touch command.
- Android Remote tab untuk connect/disconnect, trackpad, click, scroll, live typing, special keys, media play/pause, dan zoom.
- State server sekarang menyertakan status control channel.

Catatan implementasi:

- HTTP server tetap di port `8765`.
- Channel control hanya menerima device yang sudah trusted lewat pairing.
- Worker tidak menjadi authority keamanan; validasi command tetap dilakukan di `pc_app`.
- Dependency worker dicatat di `pc_worker/requirements.txt`.

Belum dikerjakan di fase ini:

- Voice typing.
- Audio streaming dari PC ke Android.
- Screen mirror.
- Discovery otomatis.
- Full integration test lintas device.
