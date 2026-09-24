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

The window has a sidebar with 查词 Lookup, 截图翻译 Screenshot, the 取词 Word capture and 划词 Select text switches, 文档翻译 Documents and 设置 Settings, followed by your favourites (click one to look it up).
Below 640 points wide the sidebar shows icons only; the window can be as small as 520 x 380.
On the Lookup page, type a word, phrase or paragraph and press Enter (or click the round arrow button).
Shift+Enter adds a new line.
Before a search, the page shows the three shortcuts, cards to start screenshot translation, switch select to translate and word capture, or open Documents, and a Sources card showing which translation sources are configured.
When the input is focused and empty, a list of the last 10 lookups drops down under it, each with a short meaning remembered from its last lookup; typing filters the list, clicking a row searches it again, "清空 Clear" empties the history, and Esc or a click elsewhere hides it.
Deleting all the text clears the result at once.

How a lookup is answered:

- One line under 60 characters (a word or a short phrase, English or Chinese) is looked up in the Youdao dictionary first.
  If Youdao has an entry, the result shows it: UK and US phonetics with play buttons (pinyin for Chinese), the concise senses with the part of speech (n., v., adj. and so on) in front of each line, and a row of web translations.
  For a single English word, the Wiktionary "English definitions" are below, collapsed.
- If Youdao has no entry, and for longer or multi-line text, the enabled sources in Settings > API > "翻译顺序 Translation order" are tried in that order (by default: your APIs, then Google, Apple Translation, MyMemory).
  An API without a key is skipped; a source that fails passes to the next one; the free sources get 8 seconds each; if every source fails, all their errors are shown together.
  A short phrase shows up to 5 candidate translations (API or MyMemory), longer text one translation that keeps line breaks.
  Pinned screenshots, select to translate, word capture, Option+D and Documents use the same order.

Every result shows which source answered: "Youdao", "API name · model", "Google", "Apple Translation" or "MyMemory".
When sources before it were skipped or failed, a small note says which and why.

Closing the window keeps the app running (this can be changed in Settings); click the Dock icon or press Option+Space to bring it back.

## Select to translate

Turn on "划词翻译 Select to translate" in Settings > System (or on the Lookup page).
It needs Accessibility permission: macOS asks the first time; turn on Mini Dict in System Settings > Privacy & Security > Accessibility.
When you select text in another app, a small button appears next to the selection (or, with "自动显示 Show automatically", the translation right away); clicking it shows a small panel under the selection with the same result as the Lookup page and a link to open it in the main window.
Clicking elsewhere, selecting something else, or Esc hides the panel; pinned screenshots still take Esc first.
Apps that do not expose the selected text to Accessibility (some browsers and PDF viewers) work only with "剪贴板回退 Clipboard fallback" on, which copies the selection with Cmd+C and puts your clipboard back afterwards.
Selections inside Mini Dict are ignored.

## Word capture

Turn on "取词 Word capture" in the sidebar or on the Lookup page.
Hold Option and rest the pointer on a word in any app for a moment: a small area around the pointer is captured (Screen Recording permission), read with Vision, and the word under the pointer is looked up in the same small panel as select to translate.
Moving the pointer away or releasing Option hides it.

## Documents

The 文档翻译 Documents page translates a whole file paragraph by paragraph: drop a file on the window or click +.
Supported: PDF, Word (.docx), PowerPoint (.pptx), Excel (.xlsx, cell texts), EPUB, plain text and Markdown, and images (read with Vision).
Each paragraph shows the original with its translation below, filled in as translations arrive (up to 3 at a time, pieces of up to 1500 characters) with a progress bar and a Cancel button; a paragraph that fails shows its error in red.
"导出译文 Export translation" saves a bilingual Markdown file (.md) or the translation only (.txt); "复制全部 Copy all" copies the translation; "清除 Clear" starts over.
"问答速读 Q&A" sends a question with the document text (up to 60,000 characters, with a note when it is cut) to the API and shows the answer; it needs a DeepSeek or OpenAI key.

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
- System: launch at login, show the menu bar icon, keep running when the window closes, and select to translate.
- API:
  - "翻译顺序 Translation order": every API you added plus Google, Apple Translation and MyMemory, in the order they are tried. Drag a row, or use its up and down arrows, to move it; its switch turns the source on or off; the first enabled source is marked "默认 Default". "恢复默认顺序 Reset order" puts your APIs first, then Google, Apple Translation, MyMemory, all on.
  - Your APIs: "添加 API Add API" adds an empty card, "+ DeepSeek" and "+ OpenAI" add a filled-in one. Each card has a name, base URL, key, model and format: OpenAI compatible (`{base}/chat/completions`), Anthropic (`{base}/messages`) or Gemini (`{base}/models/{model}:generateContent`), plus Test and Delete. You can add as many as you like; deleting one removes it from the order.
  - Every field is saved as soon as you change it; pressing Enter in a key field, or leaving it, tests that API and shows the result under the key.
  - The APIs are asked for natural, idiomatic wording.
  - Settings, including the keys, are stored in the app's preferences (`defaults read local.mini-dict`, the APIs under `providers`); the older DeepSeek and OpenAI settings are moved into two cards once.

## Data sources

- Dictionary senses, phonetics, web translations and audio: Youdao dictionary, an unofficial public endpoint, https://dict.youdao.com/jsonapi and https://dict.youdao.com/dictvoice (no key).
- Free translation, in this order:
  - Google, https://translate.googleapis.com/translate_a/t (an unofficial endpoint, no key; it is not reachable from mainland China, in which case the next source answers).
  - Apple Translation, on the device (macOS 26 or later); the English and Simplified Chinese language packs must be downloaded in System Settings > General > Language & Region > Translation Languages, otherwise it is skipped with a note.
  - MyMemory, https://api.mymemory.translated.net (no key, a daily limit; long text is sent in pieces of up to 450 characters).
- English definitions and examples: Wiktionary REST API, https://en.wiktionary.org/api/rest_v1/page/definition/.
- API translation: any OpenAI-compatible, Anthropic or Gemini API you add, with your own keys.
- Text recognition: Apple Vision framework, on the device.
