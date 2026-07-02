# Repair Phase 7 - Clipboard and Quick Actions Parity

Status: complete.

Fase ini mengunci ulang clipboard, URL, continue intent, dan command whitelist agar manual actions dan NFC actions memakai kontrak yang sama dengan reference.

## Intent Matrix

| Intent/action | Android caller | PC behavior |
| --- | --- | --- |
| `url` | Actions tab `Open on PC` | PC membuka target URL/path lewat local opener |
| `clipboard` | Actions tab `Send to PC` | PC menulis text ke clipboard |
| `GET /api/clipboard` | Actions tab dan NFC quick action | Android menyalin clipboard PC ke clipboard Android |
| `command/open_chrome` | Actions tab dan NFC quick action | PC membuka Chrome |
| `command/lock_pc` | Actions tab dan NFC quick action | PC lock workstation |
| `command/sleep_pc` | Actions tab dan NFC quick action | PC request sleep |
| `continue` | Server compatibility path | Delegates to `url` bila payload URL ada, atau `clipboard` bila payload text ada |

## Perubahan

- URL action di Android sekarang menolak URL kosong sebelum request dikirim.
- Config migration sekarang melengkapi missing `allowed_commands`, bukan hanya membuat whitelist ketika field belum ada.
- `open_chrome` fallback dikembalikan mendekati reference:
  - coba path Chrome umum;
  - bila tidak ketemu, jalankan `cmd /c start "" chrome`;
  - tidak lagi fallback ke URL biasa.

## Command Whitelist

Default allowed commands yang dijaga:

- `open_inbox`
- `open_downloads`
- `open_chrome`
- `lock_pc`
- `sleep_pc`

Config lama yang sudah ada akan dinormalisasi agar command di atas tetap tersedia.

## Detail Yang Dipertahankan

- Protected request tetap memakai:
  - `X-Device-Id`
  - `X-Device-Token`
- Pairing tetap memakai:
  - `X-Pairing-Token`
- NFC command payload tetap:
  - `type: command`
  - `source: nfc`
  - `payload.command_id`
- Manual Android command payload tetap:
  - `type: command`
  - `source: android`
  - `payload.command_id`

## File

- `android_app/lib/main.dart`
- `pc_app/src/config.mjs`
- `pc_app/src/server.mjs`
- `android_app/android/app/src/main/kotlin/com/smartmpc/app/NfcLaunchActivity.kt`

## Verification

- `flutter analyze`: no issues.
- `:app:compileDebugKotlin`: success.
- `npm.cmd run check`: success.
