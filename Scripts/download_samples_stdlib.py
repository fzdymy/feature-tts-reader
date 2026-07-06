#!/usr/bin/env python3
"""Download TTS audio samples using only stdlib + curl/ffmpeg.
   No pip packages required."""

import os, re, subprocess, sys, time, urllib.request
from html.parser import HTMLParser
from urllib.parse import urljoin, urlparse

OUTPUT = os.path.join(os.path.dirname(__file__), "..",
                      "Sources/FeatureTTSReaderApp/Models/default_samples")
os.makedirs(OUTPUT, exist_ok=True)

# Sources: (name, url)
SOURCES = [
    ("qwen3tts", "https://qwen.ai/blog?id=qwen3tts-0115"),
    ("indextts2", "https://index-tts.github.io/index-tts2.github.io/"),
    ("paddlespeech", "https://www.aidoczh.com/paddlespeech/tts/demo.html"),
]

class AudioFinder(HTMLParser):
    def __init__(self):
        super().__init__()
        self.urls = []

    def handle_starttag(self, tag, attrs):
        d = dict(attrs)
        if tag in ("audio", "source"):
            s = d.get("src", "")
            if re.search(r"\.(wav|mp3|ogg|m4a|flac|aac)$", s, re.I):
                self.urls.append(s)
        elif tag == "a":
            s = d.get("href", "")
            if re.search(r"\.(wav|mp3|ogg|m4a|flac|aac)$", s, re.I):
                self.urls.append(s)

def fetch_page(url):
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.read().decode("utf-8", errors="replace")
    except Exception as e:
        print(f"  FAIL fetch {url}: {e}")
        return ""

def download_file(url, dest):
    if os.path.exists(dest) and os.path.getsize(dest) > 1000:
        return True
    try:
        subprocess.run(["curl", "-fsSL", "-o", dest, url],
                       check=True, timeout=120, capture_output=True)
        size = os.path.getsize(dest)
        if size > 1000:
            print(f"  OK  {os.path.basename(dest)} ({size//1024}KB)")
            return True
        print(f"  TOO SMALL {os.path.basename(dest)} ({size}B)")
        return False
    except Exception as e:
        print(f"  FAIL {url}: {e}")
        return False

def to_wav(src, dst):
    if os.path.exists(dst) and os.path.getsize(dst) > 1000:
        return
    try:
        subprocess.run(["ffmpeg", "-y", "-i", src,
                        "-ar", "16000", "-ac", "1", "-sample_fmt", "s16",
                        dst],
                       check=True, timeout=60, capture_output=True)
        print(f"  WAV  {os.path.basename(dst)}")
    except Exception as e:
        print(f"  CONV FAIL {src}: {e}")

def scrape_source(name, url):
    print(f"\n=== {name}: {url}")
    html = fetch_page(url)
    if not html:
        return 0

    finder = AudioFinder()
    finder.feed(html)
    urls = list(set(finder.urls))

    if not urls:
        print(f"  No audio links found (site may be JS-rendered)")
        return 0

    outdir = os.path.join(OUTPUT, name)
    os.makedirs(outdir, exist_ok=True)

    count = 0
    for au in urls:
        full = urljoin(url, au)
        fname = os.path.basename(urlparse(full).path)
        if not fname or not re.search(r"\.\w+$", fname):
            fname = f"audio_{count}.wav"
        raw_path = os.path.join(outdir, fname)
        if not download_file(full, raw_path):
            continue
        # Convert non-WAV to WAV
        base = os.path.splitext(fname)[0]
        wav_path = os.path.join(outdir, f"{base}.wav")
        if not fname.lower().endswith(".wav"):
            to_wav(raw_path, wav_path)
            count += 1
        else:
            count += 1
        time.sleep(0.5)
    return count

def main():
    total = 0
    for name, url in SOURCES:
        n = scrape_source(name, url)
        total += n
        time.sleep(2)
    print(f"\n=== Done: {total} new audio files ===")

if __name__ == "__main__":
    main()
