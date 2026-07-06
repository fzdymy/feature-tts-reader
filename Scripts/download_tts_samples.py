import requests
from bs4 import BeautifulSoup
import os
import re
import time
from urllib.parse import urljoin, urlparse

# ================== 配置 ==================
URLS = [
    "https://qwen.ai/blog?id=qwen3tts-0115",
    "https://index-tts.github.io/index-tts2.github.io/",
    "https://www.aidoczh.com/paddlespeech/tts/demo.html"
]

OUTPUT_DIR = "tts_audio_samples"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
}

os.makedirs(OUTPUT_DIR, exist_ok=True)

def sanitize_filename(name):
    name = re.sub(r'[\\/*?:"<>|]', "_", name)
    return name[:100]  # 防止文件名过长

def download_file(url, filepath):
    try:
        r = requests.get(url, headers=HEADERS, stream=True, timeout=60)
        r.raise_for_status()
        with open(filepath, 'wb') as f:
            for chunk in r.iter_content(chunk_size=8192):
                f.write(chunk)
        print(f"✅ 下载成功: {os.path.basename(filepath)}")
        return True
    except Exception as e:
        print(f"❌ 下载失败 {url}: {e}")
        return False

def scrape_page(url):
    print(f"\n🔍 正在处理: {url}")
    try:
        resp = requests.get(url, headers=HEADERS, timeout=30)
        resp.raise_for_status()
        soup = BeautifulSoup(resp.text, 'html.parser')
        base_dir = os.path.join(OUTPUT_DIR, sanitize_filename(url.split('//')[-1].split('?')[0]))
        os.makedirs(base_dir, exist_ok=True)

        downloaded = 0
        # 查找所有 <audio> 和 <source>
        for tag in soup.find_all(['audio', 'source']):
            src = tag.get('src')
            if src and re.search(r'\.(wav|mp3|ogg|m4a|flac)', src, re.I):
                full_url = urljoin(url, src)
                filename = os.path.basename(urlparse(full_url).path) or f"audio_{downloaded}.wav"
                filepath = os.path.join(base_dir, sanitize_filename(filename))
                
                if download_file(full_url, filepath):
                    # 保存描述（尝试找附近文本）
                    desc = f"来源: {url}\n链接: {full_url}\n下载时间: {time.strftime('%Y-%m-%d %H:%M:%S')}\n\n"
                    # 尝试提取表格附近的文本
                    parent = tag.find_parent(['td', 'tr', 'div', 'p'])
                    if parent:
                        desc += parent.get_text(strip=True)[:500]
                    
                    with open(os.path.splitext(filepath)[0] + ".txt", "w", encoding="utf-8") as f:
                        f.write(desc)
                    downloaded += 1

        # 额外查找 a 标签中的音频链接
        for a in soup.find_all('a', href=True):
            href = a['href']
            if re.search(r'\.(wav|mp3|ogg)', href, re.I):
                full_url = urljoin(url, href)
                filename = os.path.basename(urlparse(full_url).path)
                filepath = os.path.join(base_dir, sanitize_filename(filename))
                if download_file(full_url, filepath):
                    downloaded += 1

        print(f"页面完成，共下载 {downloaded} 个音频文件 → {base_dir}")
    except Exception as e:
        print(f"页面处理失败 {url}: {e}")

# ================== 执行 ==================
if __name__ == "__main__":
    for url in URLS:
        scrape_page(url)
        time.sleep(2)  # 礼貌间隔
    
    print(f"\n🎉 全部下载完成！文件保存在: {OUTPUT_DIR}")
