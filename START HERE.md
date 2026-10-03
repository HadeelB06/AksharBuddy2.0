# AksharBuddy — local Wi-Fi repair

This is a separate test version. `hadeel_major project` and its installed app were not changed.

## Run on this prepared laptop

1. Connect the laptop and phone to the **same Wi-Fi or hotspot**.
2. Double-click **Start AksharBuddy.cmd**. Keep the laptop awake and the backend running.
3. Install the included **AksharBuddy.apk** on your phone once. You can transfer the APK without USB. It updates the existing app with the same package ID; export anything important before changing installed versions. This task has not installed it on your phone.
4. Open the app → Settings → **Laptop connection**. Enter the address printed by the launcher and tap **Save and check connection**.
5. Current laptop address when built: **http://192.168.29.68:5000**. This is the APK default; Wi-Fi can assign a different address later. An address saved in your old app overrides this default, so replace any saved `127.0.0.1` address.
6. Choose a photo/document → check extracted text → read/listen. **Keep my words never invokes IndicBART.**

Opening a folder in VS Code alone does not start a backend. Use the launcher, or Terminal → Run Task → Start AksharBuddy.

## If the phone cannot connect

- In Windows network settings, mark your trusted Wi-Fi/hotspot **Private**.
- Run **Enable LAN Firewall.ps1** once in an Administrator PowerShell: `powershell -ExecutionPolicy Bypass -File ".\Enable LAN Firewall.ps1"`.
- The rule allows incoming TCP 5000 from the **local subnet on Private networks only**. It does not disable the firewall. The repair task did not change your firewall automatically.
- On the phone, open `http://<laptop-address>:5000/health` in a browser. It should show `aksharbuddy` and `lan-repair-1`.
- If it fails, verify both devices are on the same network. Guest Wi-Fi/client isolation may prevent devices reaching one another; use a private hotspot instead. Do not configure internet port forwarding.
- If an older backend uses port 5000, the launcher asks you to close it; it never silently stops that backend.
- Backend logs: `local-logs/backend-error.log`. Logs contain timings, not document text.

## Offline operation

After dependencies, OCR models/language files, and device speech voices are installed, OCR and IndicBART run locally over LAN without internet. The laptop must remain on for these features. Saved readings, saved meanings/examples, reading position, typed Keep my words, and installed offline speech work on the phone without the laptop.

English, Hindi and Marathi Tesseract language files are installed on this prepared laptop. EasyOCR remains available as an offline cached fallback; it will not download weights during a request. A new laptop needs those files installed during setup. `Setup AksharBuddy.ps1` installs Python dependencies and needs internet for that initial installation. Android platform tools are optional for normal LAN use.

## Listen / saved words

Settings → **Android voice settings** opens Android Text-to-speech settings. Install an offline voice for the language you want to read; voice downloads need internet once. The app checks installed engines, language availability and offline voices, and tries another installed engine in the same language. It no longer silently reads Hindi/Marathi using an English fallback. Some engines do not provide Marathi; install an engine that does.

Words → **Open meaning and pronunciation** reopens the saved meaning and example. Tap **Hear this word** to pronounce it again. Saved details remain offline. The supplied IndicBART simplifier is not a dictionary; unavailable new word meanings are not fabricated.

## Optional USB development fallback

Run `powershell -ExecutionPolicy Bypass -File ".\Start AksharBuddy.ps1" -Usb`, then set the app address to `http://127.0.0.1:5000`. This requires Android platform tools and USB debugging. Change back to the LAN address when unplugging.

## Limits and unfinished validation

- **AI quality is not complete:** the supplied checkpoint still returned all six short test inputs unchanged. Faster OCR and output checks do not fix its training. No new checkpoint was promoted.
- Number/date/time/unit, negation, selected-name and language checks reject suspicious rewrites. They are conservative checks, **not a guarantee that meaning or every name is preserved**. Hindi/Marathi language identification remains heuristic; uncertain changed outputs are rejected.
- Handwriting and badly blurred photos are not reliable. Always check OCR against the original.
- PDF processing is bounded to 20 MB / 100 pages; image uploads retain their 10 MB limit. Large decoded images are resized to at most 2400 pixels per side before recognition.
- Physical phone Wi-Fi, actual audible TTS, hotspot behavior and live authentication need device testing. This package contains no copied private backend credentials. Guest/local reading remains available.
- This is a local development build and Flask server, not a public internet deployment or a store-ready release.

See **verification/REPORT.md** for measured timings and test evidence.
