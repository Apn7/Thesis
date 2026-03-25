import os
import urllib.request
import sys

def download_progress(block_num, block_size, total_size):
    downloaded = block_num * block_size
    if total_size > 0:
        percent = downloaded * 100 / total_size
        sys.stdout.write(f"\rDownloading: {min(100.0, percent):.1f}%")
        sys.stdout.flush()

def main():
    # We will download the tiny model which is fast and good enough for basic commands
    url = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"
    
    # Create the target directory
    target_dir = os.path.join("assets", "models")
    os.makedirs(target_dir, exist_ok=True)
    
    target_file = os.path.join(target_dir, "ggml-tiny.bin")
    
    print(f"Downloading whisper model from {url} to {target_file}...")
    urllib.request.urlretrieve(url, target_file, reporthook=download_progress)
    print("\nDownload complete!")

if __name__ == "__main__":
    main()
