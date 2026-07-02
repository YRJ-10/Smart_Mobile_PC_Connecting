# Repair Phase 4 - NFC Action Parity

Status: complete.

Fase ini memastikan seluruh quick action NFC punya jalur native yang setara dengan reference NFC. Fokusnya adalah action behavior, bukan perubahan layout umum.

## Action Matrix

| Quick action | Entry | Native behavior | PC route/side effect |
| --- | --- | --- | --- |
| `send_file` | `NfcLaunchActivity` | Buka native file picker dengan multiple selection | `POST /api/files?filename=...` |
| `pull_clipboard` | `NfcLaunchActivity` | Ambil clipboard PC lalu simpan ke Android clipboard | `GET /api/clipboard` |
| `request_files` | `NfcLaunchActivity` | Buka main app dengan deep link pending `action=request_files` | Android refresh `/api/request-files` |
| `open_chrome` | `NfcLaunchActivity` | Kirim command native langsung | `POST /api/intent`, command `open_chrome` |
| `lock_pc` | `NfcLaunchActivity` | Kirim command native langsung | `POST /api/intent`, command `lock_pc` |
| `sleep_pc` | `NfcLaunchActivity` | Kirim command native langsung | `POST /api/intent`, command `sleep_pc` |

## Perubahan

- `Run Tap Action` di Actions tab tidak lagi diblokir oleh status trust.
- Alur ini kembali mengikuti reference: native Activity tetap dibuka, lalu native action sendiri yang memberi status jika device belum trusted.
- `request_files` kembali memakai function khusus tanpa parameter, dengan deep link internal `action=request_files`.
- Urutan `runSelectedAction()` disusun mengikuti reference NFC.

## Detail Yang Dipertahankan

- Quick action dibaca dari SharedPreferences.
- Default quick action tetap `send_file`.
- Unknown quick action fallback ke file picker.
- File picker native tetap memakai:
  - `ACTION_OPEN_DOCUMENT`
  - `CATEGORY_OPENABLE`
  - MIME `*/*`
  - `EXTRA_ALLOW_MULTIPLE`
- Upload file tetap stream langsung dari `contentResolver`.
- Clipboard pull tetap memakai Android `ClipboardManager`.
- Command NFC tetap memakai payload:
  - `type: command`
  - `source: nfc`
  - `payload.command_id`

## File

- `android_app/lib/main.dart`
- `android_app/android/app/src/main/kotlin/com/smartmpc/app/NfcLaunchActivity.kt`

## Verification

- `flutter analyze`: no issues.
- `:app:compileDebugKotlin`: success.
