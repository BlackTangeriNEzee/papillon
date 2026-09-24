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

The window has a sidebar with 查词 Lookup, 截图翻译 Screenshot, 收藏 Favourites and 设置 Settings.
On the Lookup page, type a word, phrase or paragraph and press Enter (or click the round arrow button).
Shift+Enter adds a new line.
Before a search, the page shows the three shortcuts and up to 10 favourites.
When the input is focused and empty, a list of the last 10 lookups drops down under it; typing filters the list, clicking a row searches it again, "清空 Clear" empties the history, and Esc or a click elsewhere hides it.
Deleting all the text clears the result at once.

How a lookup is answered:

- One line under 60 characters (a word or a short phrase, English or Chinese) is looked up in the Youdao dictionary first.
  If Youdao has an entry, the result shows it: UK and US phonetics with play buttons (pinyin for Chinese), the concise senses with the part of speech (n., v., adj. and so on) in front of each line, and a row of web translations.
  For a single English word, the Wiktionary "English definitions" are below, collapsed.
- If Youdao has no entry, and for longer or multi-line text, the text is translated with the API (DeepSeek first, then OpenAI, see Settings), or with the free MyMemory route when no API key is saved.
  A short phrase shows up to 5 candidate translations, longer text one translation that keeps line breaks.

Every result shows which source answered: "Youdao", "DeepSeek · model", "OpenAI · model" or "Free".
When DeepSeek fails and OpenAI answers instead, a small note says why.

Closing the window keeps the app running (this can be changed in Settings); click the Dock icon or press Option+Space to bring it back.

## Menu bar

Left-click the menu bar icon to open a small quick-translate popover under it.
Type in the box and press Enter (Shift+Enter adds a new line); the result appears in the popover, answered the same way as in the main window.
The popover has the same history list under the input, and deleting the text clears the result.
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

The main window's 截图翻译 Screenshot page is for images you already have: paste an image with Cmd+V or drop one onto the window, edit the recognised text, and translate it.

## Services menu

Select text in any app, then choose "用 Mini Dict 翻译 Translate with Mini Dict" from the app menu > Services (or the right-click menu > Services).
You can give it a keyboard shortcut in System Settings > Keyboard > Keyboard Shortcuts > Services.
If it does not show up right after the first launch, log out and in again, or run `/System/Library/CoreServices/pbs -update`.

## Settings

Open Settings with Cmd+, from the menu bar icon, or from the sidebar; it is a page in the main window.

- Shortcuts: record a new key combination for each of the three shortcuts; a combination must include Command, Option or Control.
- Language: interface language, 中文 (Simplified Chinese), English, or follow the system.
- System: launch at login, show the menu bar icon, keep running when the window closes.
- API: two OpenAI-compatible chat completions APIs, DeepSeek (default base URL `https://api.deepseek.com/v1`, model `deepseek-chat`) and OpenAI (default `https://api.openai.com/v1`, `gpt-4o-mini`).
  Each has a key, a base URL and a model; an empty base URL or model uses the default shown in grey.
  A provider is used when its key is filled; each has its own Test and Clear buttons.
  Every field is saved as soon as you change it; pressing Enter in a key field, or leaving it, tests that provider and shows the result under the key.
  Text that Youdao does not answer goes to DeepSeek first; on any error it goes to OpenAI; if both fail, both errors are shown; with no key at all, the free route is used.
  The API is asked for natural, idiomatic wording.
  Settings, including the keys, are stored in the app's preferences (`defaults read local.mini-dict`); the older single API setting is moved into the OpenAI group once.

## Data sources

- Dictionary senses, phonetics, web translations and audio: Youdao dictionary, an unofficial public endpoint, https://dict.youdao.com/jsonapi and https://dict.youdao.com/dictvoice (no key).
- Free translation: MyMemory, https://api.mymemory.translated.net (free, no key, a daily limit; long text is sent in pieces of up to 450 characters).
- English definitions and examples: Wiktionary REST API, https://en.wiktionary.org/api/rest_v1/page/definition/.
- API translation: DeepSeek and OpenAI chat completions, with your own keys.
- Text recognition: Apple Vision framework, on the device.
