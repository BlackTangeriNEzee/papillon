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
Closing the window keeps the app running (this can be changed in Settings); click the Dock icon or the menu bar icon to bring it back.
The menu bar icon's right-click menu has Open, Screenshot translate, Settings and Quit.

## Global shortcuts

- Option+Space: show the window and focus the input; press again to hide it.
- Option+Shift+S: screenshot translation. Select a region; the text is read on your Mac with the Vision framework (English and Simplified Chinese), shown in an editable box, and translated with the Translate button.
- Option+D: translate the text on the clipboard. Select text in any app, press Cmd+C, then Option+D.

The shortcuts can be changed in Settings > Shortcuts, and Reset restores these defaults.
They work without Accessibility permission.
The first time the screenshot shortcut runs, macOS asks for Screen Recording permission for Mini Dict; turn it on in System Settings > Privacy & Security > Screen & System Audio Recording, then reopen the app.
Because every build is signed with the same certificate, the Screen Recording permission survives rebuilds.
You can also paste an image with Cmd+V or drop an image onto the window to read its text.

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
