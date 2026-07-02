# Repair Phase 8 - Remote UI Parity

Status: complete.

Fase ini mengembalikan bentuk Remote tab ke layout reference media remote. Fokus fase ini adalah struktur UI, ukuran relatif, grouping, dan posisi kontrol. Detail algoritma gesture/voice penuh tetap berada di Phase 9 sesuai rencana.

## Perubahan UI

- Remote tab tidak lagi berupa beberapa card terpisah.
- Layout dikembalikan menjadi satu layar kerja seperti reference:
  - header `MobilePC Control`;
  - status Wi-Fi kanan atas;
  - tombol `Mirror` dan `Audio ON/OFF` saat remote connected;
  - row PC address + auto-discover + connect/disconnect;
  - status connection kecil di bawah row;
  - live type field;
  - special keys horizontal fixed-size;
  - voice command block besar;
  - touchpad besar sebagai area dominan bawah layar.
- Mirror tetap dipisah ke tab Mirror seperti keputusan user.
- Audio toggle tetap tersedia di Remote tab.

## Reference Layout Restored

Komponen yang dipulihkan dari reference media remote:

- `PC IP Address (Auto-Scan)` field.
- Search icon button.
- `Connect` / `Disconnect` button.
- `Live Type to PC...` field.
- Clear icon pada live type field.
- Special key row:
  - `Alt+Tab`
  - `Enter`
  - `Bksp`
  - `Refresh`
  - `Copy`
  - `Paste`
- Voice command block:
  - normal state `Hold for Voice Command`
  - pressed state `Listening... (Release to Stop)`
- Touchpad:
  - expanded bottom area;
  - dark panel color;
  - large touch icon;
  - `TOUCHPAD` label;
  - hint text `Tap - 2-Finger Tap - 2-Finger Swipe`.

## Intentional Integration Adaptations

- Remote address field reuses Smart MPC `PC Address` controller.
- Auto-discover button reuses Smart MPC discovery flow.
- Connect/disconnect reuses Smart MPC authenticated remote connection.
- Mirror button switches to Smart MPC Mirror tab instead of pushing a separate route.
- Voice UI is restored now; speech recognition logic is completed in the logic phase.

## File

- `android_app/lib/main.dart`

## Verification

- `flutter analyze`: no issues.
- `:app:compileDebugKotlin`: success.
