import os, sys, json, queue, signal, sounddevice as sd
from vosk import Model, KaldiRecognizer

os.environ["VOSK_LOG_LEVEL"] = "0"

# ── paths ──────────────────────────────────────────────
base_dir    = os.path.dirname(os.path.abspath(__file__))
model_path  = os.path.join(base_dir, "model")
config_path = os.path.join(base_dir, "commands.txt")
output_file = os.path.join(base_dir, "voice_command.txt")

# ── sanity checks ──────────────────────────────────────
if not os.path.isdir(model_path):
    sys.exit("❌ Model folder not found: " + model_path)
if not os.path.isfile(config_path):
    sys.exit("❌ commands.txt not found: " + config_path)

# ── build the trigger list from commands.txt ───────────
triggers = []
with open(config_path, encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        trigger = line.split("|", 1)[0].strip().lower()
        if trigger and trigger not in triggers:
            triggers.append(trigger)

if not triggers:
    sys.exit("❌ No triggers loaded from commands.txt")

# ── load model & create grammar‑restricted recognizer ──
try:
    model = Model(model_path)
except Exception as e:
    sys.exit("❌ Failed to load model: " + str(e))

grammar_json = json.dumps(triggers)   # ← LIST, not {"phrases": …}
rec          = KaldiRecognizer(model, 16000, grammar_json)

# ── audio capture setup ────────────────────────────────
q = queue.Queue(maxsize=10)

def audio_callback(indata, frames, time, status):
    try:
        q.put(bytes(indata), block=False)
    except queue.Full:
        pass

def clean_exit(*_):
    try:
        stream.stop(); stream.close()
    except Exception:
        pass
    sys.exit(0)

signal.signal(signal.SIGINT,  clean_exit)
signal.signal(signal.SIGTERM, clean_exit)

try:
    with sd.RawInputStream(
            samplerate=16000, blocksize=8000,
            dtype="int16", channels=1,
            callback=audio_callback
        ) as stream:

        while True:
            data = q.get()
            if rec.AcceptWaveform(data):
                result = json.loads(rec.Result())
                text   = result.get("text", "").strip()
                if text:
                    with open(output_file, "w", encoding="utf-8") as f:
                        f.write(text)

except Exception as e:
    print("❌ Mic/stream error:", e)
    clean_exit()
