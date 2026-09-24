# Mini Dict

A small English-Chinese dictionary web app in plain HTML, CSS and JavaScript, with no build step.

Type a word or phrase to get up to 5 candidate translations.
Chinese input is translated to English, anything else to Simplified Chinese.
Single English words also show phonetics, audio, definitions, examples and synonyms.
Select any word or short phrase on the page to translate it in a small popup.
History and favourites are kept in the browser's `localStorage`.

## Run

```sh
cd mini-dict
python3 -m http.server 8765
```

Then open http://localhost:8765/ in a browser.

## Screenshot translation

Open "截图 OCR" in the top-right corner.
Paste a screenshot with Cmd+V or Ctrl+V anywhere on the page, drop an image, or choose a file.
The text is read in the browser with Tesseract.js (English and Simplified Chinese, loaded from cdn.jsdelivr.net), shown in an editable box, and translated with the "翻译 Translate" button.
The first run downloads the OCR language data, so it takes a while.

## Optional translation API

Open the settings (gear button) and fill in an API base URL, API key and model name for any OpenAI-compatible chat completions API.
When all three are filled, translations use that API and the result is marked "API"; otherwise the free route is used and marked "免费 Free".
API errors are shown with their HTTP status; the app does not fall back to the free route.
The settings, including the key, are stored in this browser's `localStorage`.
Some providers do not allow calls from a web page (CORS), in which case the browser blocks the request and the app shows a network error.

## Data sources

- Free translation: MyMemory, https://api.mymemory.translated.net (free, no key, 500 characters per request and a daily limit).
- Dictionary entries: Free Dictionary API, https://dictionaryapi.dev.
- OCR: Tesseract.js, https://github.com/naptha/tesseract.js.
