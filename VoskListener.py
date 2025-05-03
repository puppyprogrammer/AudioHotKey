import sys, os, queue, sounddevice as sd
from vosk import Model, KaldiRecognizer
import json
import signal

os.environ["VOSK_LOG_LEVEL"] = "0"

base_dir = os.path.dirname(os.path.abspath(__file__))
output_file = os.path.join(base_dir, "voice_command.txt")
model_path = os.path.join(base_dir, "model")

if not os.path.exists(model_path):
    sys.exit("❌ Model folder not found: " + model_path)

try:
    model = Model(model_path)
except Exception as e:
    sys.exit("❌ Failed to load model: " + str(e))

rec = KaldiRecognizer(model, 16000)
q = queue.Queue(maxsize=10)  # Limit queue size

def callback(indata, frames, time, status):
    try:
        q.put(bytes(indata), block=False)  # Non-blocking to avoid backlog
    except queue.Full:
        pass  # Discard if queue is full

# Signal handler for graceful exit
def handle_exit(signum, frame):
    print("Received signal to exit, cleaning up...")
    stream.stop()
    stream.close()
    global model, rec
    del rec
    del model  # Free model memory
    sys.exit(0)

# Register signal handlers
signal.signal(signal.SIGINT, handle_exit)
signal.signal(signal.SIGTERM, handle_exit)

try:
    with sd.RawInputStream(samplerate=16000, blocksize=8000, dtype='int16',
                           channels=1, callback=callback) as stream:
        while True:
            data = q.get()
            if rec.AcceptWaveform(data):
                result = json.loads(rec.Result())
                text = result.get("text", "").strip()
                if text:
                    with open(output_file, "w", encoding="utf-8") as f:
                        f.write(text)
except Exception as e:
    print("❌ Mic or stream error: " + str(e))
    handle_exit(0, None)
