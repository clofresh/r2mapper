# R2 Mapper

Menu-bar app that turns the R2 Bluetooth scroll ring into a slideshow clicker.

## Build & install

    ./build.sh
    cp -R "build/R2 Mapper.app" ~/Applications/

Needs **Input Monitoring** (to read the ring) and **Accessibility** (to send keys and
block the ring's own events) in System Settings → Privacy & Security.

## Default mappings

| Button      | Action                                   |
|-------------|------------------------------------------|
| Right, Down | Next slide (→)                           |
| Left, Up    | Previous slide (←)                       |
| OK          | Start slideshow (⌘↩; ⌥⌘P in Keynote)     |
| Home        | Black screen toggle (B)                  |

## Changing mappings

Menu bar icon → **Edit Mappings…** opens
`~/Library/Application Support/R2Mapper/config.json`. Changes apply on the next press.

```json
{
  "buttons": {
    "ok": { "label": "Start slideshow", "key": "return", "modifiers": ["cmd"] },
    "home": { "label": "Say hi", "shell": "say hi" }
  },
  "apps": {
    "com.apple.iWork.Keynote": {
      "ok": { "label": "Play slideshow", "key": "p", "modifiers": ["cmd", "option"] }
    }
  }
}
```

- Buttons: `up`, `down`, `left`, `right`, `ok`, `home`
- Keys: letters, digits, `left`/`right`/`up`/`down`, `return`, `space`, `escape`, `tab`,
  `pageup`/`pagedown`, `home`/`end`, `f1`–`f12`, punctuation
- Modifiers: `cmd`, `shift`, `option`, `ctrl`, `fn`
- `apps` overrides buttons when that app (by bundle ID) is frontmost.

## How it works

The ring presents itself as a keyboard + touchscreen + mouse + media keys. Up/Down/Left/Right
are fake touch swipes, OK is a tap, Home is Volume Up. macOS won't let a non-root app take
exclusive control of a keyboard-class device, so the app reads the raw HID reports
(`Sources/Ring.swift`) and uses an event tap to drop events whose sender is the ring
(`Sources/EventFilter.swift`). `Tools/capture.swift` dumps raw reports for debugging.

Run with `--debug --dry-run` from a terminal to log detected buttons without sending keys.
