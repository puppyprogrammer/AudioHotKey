# AudioHotKey

**Voice‑controlled hotkey automation for Windows**  
Runs entirely offline using AutoHotkey v2 and the Vosk speech‑recognition engine. Speak commands like “computer, notepad” or “computer, browser” to launch apps or URLs hands‑free.

---

## 📂 Project Structure

```
AudioHotKey/
├── model/                  # Vosk acoustic & language model
├── voice_command.txt       # Transcribed words (written by the Python listener)
├── voice_listener.ahk      # AutoHotkey v2 script (UI + command dispatcher)
└── VoskListener.py         # Python listener (binds microphone → voice_command.txt)
```

---

## ⚙️ Prerequisites

- **Windows 10 or later**  
- **[AutoHotkey v2](https://www.autohotkey.com/)** installed and in your PATH  
- **Python 3.x** installed and in your PATH  

---

## 🚀 Getting Started

1. **Clone or download** this repo and `cd` into `AudioHotKey/`.

2. **Install Python dependencies**  
   ```powershell
   pip install vosk
   ```
   
3. **Verify the model folder**  
   You should have a `model/` directory containing Vosk’s `.fst` graphs, acoustic model binaries, etc.  
   If it’s missing, download the “small” English model (≈ 67 MB) from  
   <https://alphacephei.com/vosk/models>  
   and unzip it here:
   ```
   AudioHotKey/
   ├── model/
   │   ├── am/
   │   ├── conf/
   │   └── graph/
   └── …
   ```

4. **Launch the AutoHotkey GUI**  
   In a separate window, double‑click:
   ```powershell
   voice_listener.ahk
   ```
   A semi‑transparent, Matrix‑style overlay will appear under your cursor.

---

## 🎤 How It Works

- **VoskListener.py**  
  - Grabs audio from your default microphone  
  - Uses the Vosk model to perform real‑time, offline speech recognition  
  - Writes recognized words (streaming) to `voice_command.txt`

- **voice_listener.ahk**  
  - Polls `voice_command.txt` every 50 ms  
  - Logs each word with a timestamp in the floating overlay  
  - When it sees a full phrase prefixed with “computer”, it matches against `RegExMatch` rules:
    - `computer notepad` → launches Notepad  
    - `computer calculator` → opens Calculator  
    - `computer browser` → opens your default browser  
    - `computer exit` → shuts down the script (and the Python listener)

---

## 🔧 Customization

1. **Add new commands**  
   Open `voice_listener.ahk` and edit the `ProcessVoiceCommand()` function.  
   Use AHK’s `Run`, `RunWait`, or COM/WinAPI calls to do anything—launch scripts, control windows, send keystrokes, etc.

2. **Adjust UI**  
   - Change `winW` / `winH` globals for overlay size  
   - Tweak `SetFont("s6 cLime","Consolas")` for font family/size/color  
   - Modify the DllCall to `SetWindowPos` for positioning behavior

3. **Model & accuracy**  
   - Drop in a larger Vosk model (e.g. “vosk‑large‑en”) under `model/` for better accuracy at the cost of disk/RAM  
   - Remove `ivector/` from the model folder to save a few MB if you don’t need speaker adaptation

---

## 🛡 License & Contributions

Released under the [MIT License](LICENSE).  
Contributions welcome! Please open an issue or submit a pull request.

---

© 2025 PuppyProgrammer
