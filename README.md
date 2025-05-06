# AudioHotKey

**Voice‑controlled hotkey automation for Windows**  
Runs entirely offline using AutoHotkey v2 and the Vosk speech‑recognition engine. Speak commands like “computer, notepad” or “computer, browser” to launch apps or URLs hands‑free. Edit the commands.txt file to add commands.

AudioHotKey Discord Group: https://discord.gg/bpTGGTdk8M 

---

## 📂 Project Structure

```
AudioHotKey/
├── model/                  # Vosk acoustic & language model
├── voice_command.txt       # Transcribed words (written by the Python listener)
├── voice_listener.ahk      # AutoHotkey v2 script (UI + command dispatcher)
└── VoskListener.py         # Python listener (binds microphone → voice_command.txt)
```

## ⚙️ Prerequisites

- **Windows 10 or later**



## 🚀 Getting Started

1. Download Release 1.0

2. Run voice_listener.exe to start the script
   

## 🎤 How It Works

- **VoskListener.py (Compiled into VoskListener.exe in Release 1.0)**  
  - Grabs audio from your default microphone  
  - Uses the Vosk model to perform real‑time, offline speech recognition  
  - Writes recognized words (streaming) to `voice_command.txt`

- **voice_listener.ahk (Compiled into voice_listener.exe in Release 1.0)**  
  - Polls `voice_command.txt` every 50 ms  
  - Logs each word with a timestamp in the floating overlay  
  - When it sees a full phrase prefixed with “computer”, it matches against `RegExMatch` rules:
    - `computer notepad` → launches Notepad  
    - `computer calculator` → opens Calculator  
    - `computer browser` → opens your default browser  
    - `terminate session` → shuts down the script (and the Python listener)

---

## 🔧 Customization

1. Add lines to the commands.txt file to add custom commands.
---


## 🛡 License & Contributions

Released under the [MIT License](LICENSE).  
Contributions welcome! Please open an issue or submit a pull request.

---

© 2025 PuppyProgrammer
