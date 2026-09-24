# Mini Dict

A small English-Chinese dictionary and translator for macOS, written in Swift with AppKit and SwiftUI.
It has a normal window, a Dock icon and a menu bar icon.
Chinese input is translated to English; anything else is translated to Simplified Chinese.

## Build

```sh
sh mac/make-cert.sh
sh mac/build.sh
```

Run `sh mac/make-cert.sh` once per Mac: it creates a self-signed code signing certificate named "Mini Dict Signing" in your login keychain, and does nothing if it already exists.
After that, `sh mac/build.sh` is all you need; it stops with a message if the certificate is missing.
The scripts need only the Xcode Command Line Tools (`swiftc`).
The app lands in `build/MiniDict.app`; open it with `open build/MiniDict.app` or copy it to `/Applications`.
The certificate is self-signed, so the first time Gatekeeper may block the app: right-click the app, choose Open, then confirm.

## Using it

Type a word, phrase or paragraph and press Enter (or click Translate).
Shift+Enter adds a new line.
A single English word shows up to 5 candidate translations, phonetics with audio, and up to 5 definitions per part of speech with examples.
A short phrase (up to 6 words, under 60 characters, one line) shows up to 5 candidate translations.
Anything longer is translated as a whole paragraph, keeping line breaks.
Every result shows which route was used: "Free" or "API".

The History tab keeps the last 20 lookups and your favourites (the star next to a result).
Closing the window keeps the app running (this can be changed in Settings); click the Dock icon or press Option+Space to bring it back.

## Menu bar

Left-click the menu bar icon to open a small quick-translate popover under it.
Type in the box and press Enter (Shift+Enter adds a new line); the result appears in the popover with the same routing as the main window: a word shows candidate translations and up to 5 definitions per part of speech, a phrase shows candidate translations, and a paragraph shows its translation.
"在主窗口打开 Open in main window" opens the main window with the same text searched.
Click outside the popover, press Esc, or click the icon again to close it.
Right-click the menu bar icon for the menu with Open, Screenshot translate, Settings and Quit.

## Global shortcuts

- Option+Space: show the window and focus the input; press again to hide it.
- Option+Shift+S: screenshot translation (also in the menu bar icon's right-click menu). See "Screenshot translation" below.
- Option+D: translate the text on the clipboard. Select text in any app, press Cmd+C, then Option+D.

The shortcuts can be changed in Settings > Shortcuts, and Reset restores these defaults.
They work without Accessibility permission.
A shortcut only works in one app at a time: if another app uses the same combination, change one of them.
For example, Easydict's screenshot OCR shortcut is also Option+Shift+S by default; while both apps use it, the other app's selector can take the first drag.

## Screenshot translation

Press Option+Shift+S: the screen dims and the pointer becomes a crosshair.
Drag a rectangle over the text; the rectangle has an accent border, corner handles and a badge with its size in pixels.
Esc, or a click without dragging, cancels.
When you release the mouse, the region is captured with ScreenCaptureKit at the screen's full resolution and pinned on the screen exactly where it was, with an accent border.
The text is read on your Mac with the Vision framework (English and Simplified Chinese).
Lines that belong together are joined into blocks, each block is translated (up to 3 at a time), and the translation is drawn over the original text in the same place, on the colour of the original background.
Until a block's translation arrives, the original stays visible; a block that fails shows its error in red.
Hover over the pinned screenshot for a small toolbar: copy all translations in reading order, switch between the translation and the original screenshot, or close it.
Several screenshots can be pinned at the same time, and you can drag them around.
While at least one screenshot is pinned, Esc closes all of them at once, whichever app is in front; that Esc press does nothing else.
When nothing is pinned, Esc works as usual again.

The first time, macOS asks for Screen Recording permission for Mini Dict; turn it on in System Settings > Privacy & Security > Screen & System Audio Recording, then reopen the app.
Until then, a pinned message explains this instead of capturing.
Because every build is signed with the same certificate, the Screen Recording permission survives rebuilds.

The main window's Screenshot tab is for images you already have: paste an image with Cmd+V or drop one onto the window, edit the recognised text, and translate it.

## Services menu

Select text in any app, then choose "用 Mini Dict 翻译 Translate with Mini Dict" from the app menu > Services (or the right-click menu > Services).
You can give it a keyboard shortcut in System Settings > Keyboard > Keyboard Shortcuts > Services.
If it does not show up right after the first launch, log out and in again, or run `/System/Library/CoreServices/pbs -update`.

## Settings

Open Settings with Cmd+, or from the menu bar icon.

- Shortcuts: record a new key combination for each of the three shortcuts; a combination must include Command, Option or Control.
- Language: interface language, 中文 (Simplified Chinese), English, or follow the system.
- System: launch at login, show the menu bar icon, keep running when the window closes.
- API: base URL, key and model for any OpenAI-compatible chat completions API, with Save, Test and Clear.
  When all three are filled, translations use that API and ask it for natural, idiomatic wording; otherwise the free route is used.
  API errors are shown with their HTTP status; the app does not fall back to the free route.
  Settings, including the key, are stored in the app's preferences (`defaults read local.mini-dict`).

## Data sources

- Free translation: MyMemory, https://api.mymemory.translated.net (free, no key, a daily limit; long text is sent in pieces of up to 450 characters).
- Definitions and examples: Wiktionary REST API, https://en.wiktionary.org/api/rest_v1/page/definition/.
- Phonetics and audio: Free Dictionary API, https://dictionaryapi.dev (6 second timeout; when it fails, the definitions still show).
- Text recognition: Apple Vision framework, on the device.
