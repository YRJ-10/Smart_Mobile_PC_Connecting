# Phase 0 Feature Lock

Tanggal: 2026-07-01

Dokumen ini mengunci cakupan fitur Smart MPC. Tujuannya sederhana: semua fitur dari dua project referensi harus masuk ke project baru tanpa mengubah project referensi.

## Aturan Source

Project referensi:

- `C:\Users\yeryi\AndroidStudioProjects\NFC_Instan_Action`
- `C:\Users\yeryi\AndroidStudioProjects\MobilePCMedia`

Aturan kerja:

- Project referensi hanya dibaca.
- Jangan edit, format, hapus, rename, atau memindahkan file di project referensi.
- Jika fitur dibutuhkan, salin bagian yang relevan ke `C:\Users\yeryi\AndroidStudioProjects\Smart_MPC`.
- Implementasi baru boleh mengubah struktur, nama modul, dan protokol selama fitur lama tetap ada.

## Konsep Utama

Smart MPC adalah satu produk dengan pola:

```text
Android app <-> jaringan lokal <-> PC local server/app <-> aksi di PC
```

Mobile menjadi controller, trigger, transfer tool, dan receiver. PC menjadi server, target aksi, streamer, dan pusat trust/auth.

## Sumber Fitur: NFC_Instan_Action

Wajib dipertahankan:

- Flutter Android app.
- PC local server berbasis Node HTTP.
- Desktop PC app berbasis Electron.
- Server auto-start ketika PC app dibuka.
- Tombol start/stop server di PC app.
- Local IP detection.
- `GET /health`.
- `GET /pair`.
- Pairing token.
- Register trusted device.
- Device id.
- Device token.
- Simpan konfigurasi di Android.
- Simpan konfigurasi server di PC.
- Trusted device list.
- Revoke trusted device.
- Request/activity log.
- Inbox folder untuk file dari HP.
- Outbox folder untuk file dari PC ke HP.
- Open inbox dari PC app.
- Open outbox dari PC app.
- Add files to outbox dari PC app.
- Copy pairing token dari PC app.
- HTTP auth memakai `X-Device-Id` dan `X-Device-Token`.
- Pairing auth memakai `X-Pairing-Token`.
- Send URL dari HP ke PC.
- Open URL di PC.
- Send clipboard dari HP ke PC.
- Pull clipboard dari PC ke HP.
- Send file dari HP ke PC.
- Request/list files dari PC outbox.
- Download file PC ke Android Downloads.
- Intent API.
- File upload API.
- Command whitelist.
- Open inbox command.
- Open downloads command.
- Open Chrome command.
- Lock PC command.
- Sleep PC command.
- Continue intent untuk URL/text.
- Find PC / scan IP subnet.
- Manual PC address input.
- Pairing code input.
- Trust phone action.
- Quick action selector.
- Run tap action simulation.
- NFC/deep link Activity.
- Deep link scheme `nfcinstant://tap`.
- NDEF discovered intent.
- NFC quick send file.
- NFC quick pull clipboard.
- NFC quick request files fallback ke main app.
- NFC quick open Chrome.
- NFC quick lock PC.
- NFC quick sleep PC.
- Lightweight native launch screen ketika NFC action berjalan.
- Android file picker dengan multiple file support.

## Sumber Fitur: MobilePCMedia

Wajib dipertahankan:

- Flutter Android remote-control app.
- Python PC server app.
- PC server window dengan START/STOP.
- Copy IP button.
- Server status display.
- Manual IP connect dari HP.
- Auto-discovery server via UDP broadcast.
- Discovery message `DISCOVER_MOBILEPC`.
- Discovery response `MOBILEPC_SERVER`.
- TCP command/control channel.
- UDP audio channel.
- TCP screen mirror channel.
- Trackpad area di HP.
- Mouse move relative.
- Left click.
- Right click.
- Scroll.
- Browser back gesture.
- Browser forward gesture.
- Zoom command.
- Media play/pause command.
- Special keys.
- Alt+Tab.
- Enter.
- Backspace.
- Refresh / F5.
- Copy.
- Paste.
- Live typing dari keyboard HP ke PC.
- Incremental typing dengan backspace handling.
- Voice typing memakai speech-to-text.
- Microphone permission request.
- Hold/tap mic behavior sesuai implementasi lama.
- Audio toggle dari HP.
- PC audio loopback capture.
- Audio stream PC ke HP.
- Android native audio receiver via `AudioTrack`.
- Low-latency PCM playback.
- Screen capture PC.
- JPEG frame encoding.
- Screen mirror page di HP.
- Landscape orientation saat mirror.
- Frame rendering via image memory.
- Touch down/move/up control di mirror.
- Coordinate mapping dari HP ke layar PC.
- Pinch/InteractiveViewer behavior di mirror.
- Disconnect confirmation.
- Connection state indicator.

## Port dan Channel Referensi

Port asal:

- NFC HTTP server: `8765`.
- MobilePCMedia TCP command: `8080`.
- MobilePCMedia UDP discovery/audio: `8081`.
- MobilePCMedia TCP video: `8082`.

Desain Smart MPC boleh mengganti port, tapi fungsi channel wajib tetap ada:

- HTTP API untuk pairing, file, clipboard, quick actions.
- Realtime control channel untuk mouse, keyboard, media, touch.
- Discovery channel.
- Audio stream channel.
- Screen stream channel.

## Modul Target Smart MPC

Struktur target awal:

```text
Smart_MPC/
+-- android_app/
+-- pc_app/
+-- pc_worker/
+-- shared_protocol/
+-- docs/
+-- README.md
```

Rencana tanggung jawab:

- `android_app`: Flutter Android app, NFC Activity, audio receiver native.
- `pc_app`: Electron desktop app dan Node server utama.
- `pc_worker`: Python worker untuk mouse/keyboard/audio/screen.
- `shared_protocol`: definisi message, endpoint, command id, dan auth model.
- `docs`: checklist, roadmap, dan catatan integrasi.

## Model Keamanan Target

Semua fitur remote harus berada di bawah trust/auth dari sistem pairing.

Wajib ada:

- Pairing token.
- Trusted device.
- Device id.
- Device token.
- Revoke device.
- Request log.
- Permission/toggle untuk fitur berisiko.

Catatan penting: fitur remote-control dari MobilePCMedia tidak boleh tetap menjadi channel bebas tanpa trust. Saat digabung, command live harus hanya diterima dari device trusted.

## Checklist Integrasi

Status:

- `[source]` fitur sudah ada di project referensi.
- `[planned]` fitur belum masuk Smart MPC.
- `[ported]` fitur sudah disalin/diadaptasi ke Smart MPC.
- `[verified]` fitur sudah lulus testing akhir.

### Connection, Pairing, Auth

- [planned] Local server PC.
- [planned] Local IP detection.
- [planned] Manual IP connect.
- [planned] Auto-discovery.
- [planned] Pairing token.
- [planned] Trust phone/register device.
- [planned] Device id/token storage.
- [planned] Auth headers/session for protected routes.
- [planned] Trusted device list.
- [planned] Revoke device.
- [planned] Request/activity log.

### File and Clipboard

- [planned] Send file HP ke PC.
- [planned] Multiple file upload.
- [planned] PC inbox.
- [planned] PC outbox.
- [planned] Add files to outbox.
- [planned] Request/list PC files.
- [planned] Download PC files to Android Downloads.
- [planned] Send clipboard HP ke PC.
- [planned] Pull clipboard PC ke HP.

### Quick Actions and NFC

- [planned] Quick action selector.
- [planned] Run tap action simulation.
- [planned] NFC/deep link launch.
- [planned] `nfcinstant://tap` compatible route or migration route.
- [planned] NDEF discovered support.
- [planned] NFC send file.
- [planned] NFC pull clipboard.
- [planned] NFC request files fallback.
- [planned] NFC open Chrome.
- [planned] NFC lock PC.
- [planned] NFC sleep PC.
- [planned] Open URL on PC.
- [planned] Continue intent URL/text.
- [planned] Command whitelist.
- [planned] Open inbox command.
- [planned] Open downloads command.

### Remote Control

- [planned] Realtime control channel.
- [planned] Trackpad mouse move.
- [planned] Left click.
- [planned] Right click.
- [planned] Scroll.
- [planned] Browser back.
- [planned] Browser forward.
- [planned] Zoom.
- [planned] Media play/pause.
- [planned] Alt+Tab.
- [planned] Enter.
- [planned] Backspace.
- [planned] Refresh/F5.
- [planned] Copy.
- [planned] Paste.
- [planned] Live typing.
- [planned] Incremental typing/backspace handling.
- [planned] Voice typing.
- [planned] Microphone permission.

### Audio and Screen

- [planned] Audio toggle.
- [planned] PC audio loopback capture.
- [planned] UDP/realtime audio stream.
- [planned] Android native audio receiver.
- [planned] PCM playback via AudioTrack.
- [planned] Screen capture.
- [planned] JPEG/video frame stream.
- [planned] Screen mirror page.
- [planned] Landscape mirror mode.
- [planned] Touch control on mirror.
- [planned] Coordinate mapping.
- [planned] InteractiveViewer/pinch behavior.

### PC App UX

- [planned] Desktop app shell.
- [planned] Server auto-start.
- [planned] Start/stop server button.
- [planned] IP display.
- [planned] Pairing token display.
- [planned] Copy token.
- [planned] Open inbox.
- [planned] Open outbox.
- [planned] Add outbox files.
- [planned] Trusted device list.
- [planned] Revoke device UI.
- [planned] Activity log.
- [planned] Server status.
- [planned] Copy IP.

### Android UX

- [planned] Connect screen.
- [planned] Find PC/search button.
- [planned] Manual IP input.
- [planned] Pairing code input.
- [planned] Connected/trusted indicator.
- [planned] Disconnect confirmation.
- [planned] Home/dashboard.
- [planned] Quick actions screen.
- [planned] Files screen.
- [planned] Clipboard controls.
- [planned] Remote screen.
- [planned] Mirror screen.
- [planned] Audio control.
- [planned] Settings screen.

## Fase Berikutnya

Fase 1 adalah membuat struktur project baru di root `Smart_MPC`:

- `android_app/`
- `pc_app/`
- `pc_worker/`
- `shared_protocol/`
- starter README per modul
- protocol skeleton

Fase 1 belum perlu full test. Sanity check cukup memastikan struktur, file awal, dan arah modul sudah rapi.
