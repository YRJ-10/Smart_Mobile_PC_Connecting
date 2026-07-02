# Repair Phase 1 - Reference Mapping

Status: complete.

Tujuan fase ini adalah memetakan fitur ke implementasi acuan sebelum porting ulang. Fase ini tidak mengubah logic aplikasi.

## Keputusan Utama

Smart MPC harus diperbaiki dengan pola:

1. Copy perilaku dari reference.
2. Adapt minimal untuk nama package/app dan auth gabungan.
3. Integrasikan ke tab/layout Smart MPC.
4. Baru setelah itu uji holistik.

Yang tidak boleh terjadi lagi:

- Membuat ulang trackpad dari interpretasi umum.
- Mengganti protocol lama tanpa compatibility bridge.
- Menghapus tombol/toggle/lifecycle yang sudah terbukti.
- Menganggap layout lama hanya kosmetik.

## Connect Tab

Source of truth:

- NFC reference: `android_app/lib/main.dart`
- NFC reference: `Pc Local Server/server.mjs`
- Smart MPC current: `android_app/lib/main.dart`

Yang dipertahankan dari Smart MPC:

- Device section.
- Clear local trust.
- Discovered PCs, selama benar-benar bisa memilih/mengisi PC address.

Yang harus dihapus dari UI:

- Health button/section.
- Pair Info button/section.
- PC Addresses section.

Yang harus tetap ada:

- PC Address input.
- Pairing token input.
- Find PC.
- Trust Phone.
- Save.
- Device info.
- Clear Local Trust.
- Discovered PCs.

Find PC target behavior:

- Klik Find PC harus mencari PC di jaringan lokal.
- Jika ditemukan, PC Address otomatis terisi.
- Jika ada daftar discovered PCs, tap item harus mengisi PC Address.
- Tombol tidak boleh hanya kosmetik.

Trust/Save target behavior:

- Trust Phone memakai endpoint register dengan pairing token.
- Save menyimpan PC address, pairing token, device id, device token, pc id, dan quick action.
- Setelah app dibuka ulang, user tidak perlu isi ulang token/address bila sebelumnya sudah disimpan.

## NFC Quick Action

Source of truth:

- NFC reference: `AndroidManifest.xml`
- NFC reference: `MainActivity.kt`
- NFC reference: `NfcLaunchActivity.kt`
- NFC reference: `android_app/lib/main.dart`

Detail yang harus dipertahankan:

- Activity NFC native terpisah.
- Activity punya native launch screen ringan.
- Mulai proses setelah window focus.
- Delay sebelum aksi: 250 ms.
- Quick action dibaca dari SharedPreferences.
- File action membuka native file picker.
- Request files membuka main app dengan pending/deep link action.
- Clipboard/command action dieksekusi langsung dari Activity native.
- Activity menutup diri dengan delay pendek setelah aksi selesai.
- `ACTION_OPEN_DOCUMENT`, `CATEGORY_OPENABLE`, `*/*`, dan multiple file harus tetap.
- Upload native harus streaming langsung dari content resolver, bukan base64.
- Download request file harus memakai DownloadManager.

Smart MPC current:

- Sudah punya `NfcLaunchActivity.kt`, tetapi harus dibandingkan baris per baris dengan NFC reference sebelum fase NFC.
- Deep link sudah diganti ke skema Smart MPC. Ini boleh, selama manifest/NFC tag nanti konsisten dan lifecycle lama tidak berubah.

## Actions Tab

Source of truth:

- NFC reference: `android_app/lib/main.dart`
- NFC reference: `Pc Local Server/server.mjs`

Yang bisa dipertahankan:

- Pengelompokan section Smart MPC saat ini.
- Quick action dropdown.
- Manual URL/clipboard section.

Yang harus dikunci ke reference:

- Request files memakai PC outbox.
- Android hanya refresh list dari `/api/request-files`.
- Tiap file punya icon download.
- Download memakai `/api/request-files/download?filename=...` dan DownloadManager.
- Pick and upload file memakai native picker dan `POST /api/files`.

Endpoint parity:

- `POST /api/intent` untuk `url`, `clipboard`, `command`, `continue`.
- `GET /api/clipboard`.
- `POST /api/files`.
- `GET /api/request-files`.
- `GET /api/request-files/download`.

## Remote Tab UI

Source of truth:

- Media reference: `flutter_client/lib/main.dart`

Smart MPC current:

- Remote tab sekarang terlalu berbeda dari layout reference.
- Trackpad sekarang hanya area 260 px dengan tombol klik/scroll terpisah.
- Ini tidak memenuhi permintaan user.

Target:

- Remote tab harus mengikuti layout reference secara literal.
- Mirror boleh tetap tab terpisah.
- AppBar/toolbar remote harus mempertahankan tombol/toggle penting: Mirror dan Audio ON/OFF.
- Connect row, live type field, special key row, voice command area, dan touchpad besar harus kembali mengikuti reference.
- Ukuran relatif trackpad harus tetap menjadi area dominan bawah layar.
- Tombol special key fixed-size seperti reference: Alt+Tab, Enter, Bksp, Refresh, Copy, Paste.
- Voice command long-press tetap ada.
- Keyboard close behavior harus dipertahankan: ketika keyboard tertutup, unfocus dan clear text.

## Remote Logic

Source of truth:

- Media reference: `flutter_client/lib/main.dart`
- Media reference: `python_server/server.py`

Protocol:

- TCP `8080`.
- newline-delimited JSON.
- `tcpNoDelay`.

Commands:

- `MOUSE_MOVE`
- `MOUSE_CLICK`
- `TYPE_TEXT`
- `SCROLL`
- `AUDIO_TOGGLE`
- `SPECIAL_KEY`
- `ZOOM`
- `MEDIA`
- `TOUCH_DOWN`
- `TOUCH_MOVE`
- `TOUCH_UP`

Trackpad constants to restore:

- Move throttle: 16 ms.
- Move sensitivity: 4.0.
- Scroll event threshold: `dy.abs() > 0.3`.
- Scroll sent from Android: `-dy * 0.5`.
- Server scroll multiplier: `dy * 60`.
- Left tap threshold: distance `< 400`, duration `< 350 ms`.
- Right tap threshold: distance `< 500`, duration `< 400 ms`.
- Two-finger horizontal swipe maps to `browserback` and `browserforward`.

Smart MPC current:

- Uses simplified `_lastPointerPosition`.
- Throttle is 12 ms.
- Does not preserve multi-pointer peak logic.
- Does not preserve sensitivity 4.0.
- Therefore it must be replaced by reference logic, then minimally adapted.

## Live Typing And Voice

Source of truth:

- Media reference: `flutter_client/lib/main.dart`

Live typing target:

- Keep `_lastText`.
- Calculate common prefix.
- Send one `backspace` command per removed char.
- Send only newly added substring.
- Clear `_lastText` when input is cleared/keyboard closes.

Voice target:

- Keep `speech_to_text`.
- Request microphone permission.
- Long press starts listening.
- Release stops listening.
- Send only new recognized words compared to previous recognition.

Smart MPC current:

- Live typing partially exists but lacks full keyboard-close behavior from reference.
- Voice command is absent and must be ported.

## Audio

Source of truth:

- Media reference: `flutter_client/android/.../MainActivity.kt`
- Media reference: `flutter_client/lib/main.dart`
- Media reference: `python_server/server.py`

Target behavior:

- Android MethodChannel equivalent must preserve start/stop order and low-latency AudioTrack behavior.
- Sample rate `16000`.
- Mono PCM 16-bit.
- Android UDP receive port `8081`.
- Server captures loopback audio and sends UDP packets to phone.
- Toggle sends `AUDIO_TOGGLE` and starts/stops Android receiver accordingly.

Smart MPC current after Repair Phase 10:

- Uses the reference-style audio worker based on `soundcard`.
- Android native receiver uses low-latency `AudioTrack.Builder` behavior.
- If audio fails in holistic testing, debug against the reference flow first.

## Mirror

Source of truth:

- Media reference: `flutter_client/lib/screen_mirror.dart`
- Media reference: `python_server/server.py`

Target behavior:

- TCP `8082`.
- Android enters landscape on mirror page and returns portrait on exit.
- Stream parser reads 4-byte big-endian frame length, then exact JPEG bytes.
- Render uses `Image.memory`, `gaplessPlayback: true`, `fit: BoxFit.fill`.
- UI is full black, 16:9, with simple back button overlay.
- 1 pointer sends `TOUCH_DOWN/MOVE/UP` with normalized `rx/ry`.
- 2 pointers release touch using `TOUCH_UP`.
- Server captures primary monitor, resizes to `1280x720`, JPEG quality `50`.

Smart MPC current:

- Mirror is embedded in a tab and adds auth handshake before frames.
- Worker uses FPS 8, JPEG quality 55, and dynamic height.
- This differs from reference. If auth handshake is kept, Android parser and server framing must still preserve the reference frame stream after handshake.
- Preferred fix: keep Mirror as separate tab entry, but the mirror view itself should be reference-like.

## Discovery

Source of truth:

- Media reference: `flutter_client/lib/main.dart`
- Media reference: `python_server/server.py`
- NFC reference: `android_app/lib/main.dart`
- NFC reference: `Pc Local Server/server.mjs`

Target behavior:

- Find PC should support the existing Smart MPC discovery if useful.
- It must also stay compatible with old `DISCOVER_MOBILEPC` -> `MOBILEPC_SERVER`.
- It should fill PC Address automatically.
- It should not require user to manually copy IP when discovery succeeds.

Smart MPC current:

- Already broadcasts `DISCOVER_SMART_MPC` and `DISCOVER_MOBILEPC`.
- Parser expects JSON but has partial fallback.
- Needs verification and cleanup in the Connect tab phase.

## PC Server

Source of truth:

- NFC reference: `Pc Local Server/server.mjs`
- Media reference: `python_server/server.py`

Smart MPC current:

- HTTP server is mostly good.
- Trust/auth and outbox flow are close to NFC reference.
- Control server adds auth handshake before accepting remote commands.
- Screen server adds auth handshake before video stream.

Decision:

- PC server can keep Smart MPC's safer auth where it does not break Android parity.
- It must remain compatible with old command payloads and timing.
- Worker behavior must match Media reference before optimizing.

## Phase 1 Output For Next Phases

Next implementation phases should use this order:

1. Connect tab cleanup and Find PC behavior.
2. NFC native parity.
3. Actions/request files parity.
4. Remote UI parity.
5. Remote gesture/command parity.
6. Audio parity.
7. Mirror parity.
8. Discovery and PC bridge cleanup.

No feature is considered fixed until it is traced back to the reference behavior above.
