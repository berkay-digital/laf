# Laf for Windows

Hold **Right Ctrl**, speak, and let go. whisper.cpp transcribes the audio on your PC, the chat model you set up cleans it, and Laf pastes the result into the focused text field. Tap Right Ctrl instead of holding it for hands-free mode, and tap again to finish. Esc cancels.

This is a Python port of the macOS app. The prompts and the `memory.json` format are the same, so you can copy your word list between machines.

## Install

1. Open PowerShell in this folder as your normal user (not as administrator) and run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\setup.ps1
   ```

   The script installs [uv](https://docs.astral.sh/uv/) if it's missing, creates a Python 3.12 environment in `%LOCALAPPDATA%\Laf`, downloads whisper.cpp and a speech model, runs a self-test and starts Laf. With an NVIDIA GPU it uses the CUDA build and the `large-v3-turbo` model. Otherwise it uses the CPU build and `small.en`. Run it again any time to update. It keeps your settings and words.

2. In Windows Settings, go to Privacy & security, then Microphone. Turn on "Microphone access" and "Let desktop apps access your microphone".

3. Right-click the Laf tray icon and choose **Set API key…**. See the main [README](../README.md#set-up-the-language-model) for which APIs work.

To check that it works, open Notepad, hold Right Ctrl, say "um this is a test no wait a quick test" and let go. You should get "This is a quick test."

Laf adds itself to `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` so it starts when you sign in. Turn that off with **Launch at login** in the tray menu.

## Files

- `%APPDATA%\Laf\config.json` has your settings. Restart Laf after editing it: choose **Quit Laf** in the tray, then run setup again or start `pythonw.exe laf.pyw` from `%LOCALAPPDATA%\Laf`.
- `%APPDATA%\Laf\memory.json` is your word list. `history.jsonl` records what you said and what was typed, if **Save history** is on.
- `%LOCALAPPDATA%\Laf\` holds the app, the Python environment, whisper.cpp, the models, `laf.log` and `whisper.log`.

## Troubleshooting

- **The hotkey does nothing.** Find the name the `keyboard` package uses for your key. Run `& "$env:LOCALAPPDATA\Laf\.venv\Scripts\python.exe" -c "import keyboard; print(keyboard.read_event())"`, press the key, and put that name in `hotkey` (for example `"right ctrl"` or `"right alt"`). Windows also blocks hotkeys and pasting while an app running as administrator has focus.
- **"Transcription failed."** Check `whisper.log`. If the CUDA build won't start because of a missing driver or DLL, delete `%LOCALAPPDATA%\Laf\whisper`, change `$asset` in `setup.ps1` to `whisper-bin-x64.zip`, and run setup again. You can point `whisperModel` in `config.json` at `ggml-small.en-q5_1.bin` for CPU speed.
- **It's slow on CPU.** Raise `whisperThreads` if the PC isn't busy with other work. `ggml-base.en-q5_1.bin` is faster but less accurate.
- **Edits aren't learned in one app.** That app doesn't expose its text field through UI Automation. Use **Add word…** in the tray menu instead.
