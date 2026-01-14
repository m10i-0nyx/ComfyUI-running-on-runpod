from urllib.parse import urlparse, parse_qs
import http.server
import math
import os
import socketserver
import tarfile
import tempfile
import threading
import time

# -----------------------------
# 設定
# -----------------------------
PORT = int(os.environ.get("COMFYUI_PREVIEW_GALLERY_PORT", 8888))

OUTPUT_DIR = os.path.abspath(
    "/workspace/output"  # ComfyUI の出力フォルダパスに合わせる
)

PAGE_SIZE = int(os.environ.get("COMFYUI_PREVIEW_GALLERY_PAGE_SIZE", 10))  # 1ページあたりの画像数（0で全件表示）
IMAGE_EXTS = ('.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.mp4', '.avi', '.webm')

# -----------------------------------------------
# TAR ファイルバックグラウンド生成の状態管理
# -----------------------------------------------
class TarGeneratorState:
    def __init__(self):
        self.tar_path: str | None = None  # 生成されたTARファイルのパス
        self.lock = threading.Lock()
        self.generating = False  # 生成中フラグ

tar_generator = TarGeneratorState()

def request_make_tar(images_list):
    """バックグラウンドでTARファイルを生成（同時に1リクエストのみ処理）"""
    with tar_generator.lock:
        if tar_generator.generating:
            # 既に生成中なら何もしない
            return
        tar_generator.generating = True

    def _generate():
        try:
            if not images_list:
                tar_generator.tar_path = None
                return

            # 既存のTARファイルを削除
            if tar_generator.tar_path and os.path.exists(tar_generator.tar_path):
                try:
                    os.remove(tar_generator.tar_path)
                except Exception:
                    pass

            # 新しい一時ファイルでTAR作成
            tmp = tempfile.NamedTemporaryFile(suffix='.tar', delete=False, dir=OUTPUT_DIR)
            tmp_path = tmp.name
            tmp.close()

            with tarfile.open(tmp_path, 'w:') as tf:
                for full, rel in images_list:
                    try:
                        tf.add(full, arcname=rel)
                    except Exception:
                        # 個別ファイル書込失敗は無視して続行
                        continue

            # 成功したら保存
            with tar_generator.lock:
                tar_generator.tar_path = tmp_path
        finally:
            with tar_generator.lock:
                tar_generator.generating = False

    # バックグラウンドスレッドで実行
    thread = threading.Thread(target=_generate, daemon=True)
    thread.start()

def remove_tar():
    """生成されたTARファイルを削除（新規生成可能にする）"""
    with tar_generator.lock:
        if tar_generator.tar_path and os.path.exists(tar_generator.tar_path):
            try:
                os.remove(tar_generator.tar_path)
            except Exception:
                pass
        tar_generator.tar_path = None

# -----------------------------
# HTTP サーバスレッド
# -----------------------------
class ThreadedHTTPServer(threading.Thread):
    def __init__(self, directory, port):
        super().__init__()
        self.directory = directory
        self.port = port
        self.daemon = True

    def run(self):
        os.chdir(self.directory)

        class GalleryHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
            images_cache: list[tuple[str, str]] = []
            images_cache_time: float = 0.0

            def __init__(self, *args, directory=None, **kwargs):
                super().__init__(*args, directory=directory, **kwargs)

            def collect_all_images(self):
                now = time.time()
                TTL = 60  # 秒

                cached = self.images_cache
                cached_time = self.images_cache_time

                if cached is not None and (now - cached_time) < TTL:
                    return cached

                imgs = []
                for root, _, files in os.walk(os.getcwd()):
                    for f in files:
                        if f.lower().endswith(IMAGE_EXTS):
                            full = os.path.join(root, f)
                            rel = os.path.relpath(full, os.getcwd())
                            imgs.append((full, rel))

                def _ctime(path):
                    try:
                        return os.path.getctime(path)
                    except Exception:
                        return 0

                imgs.sort(key=lambda t: _ctime(t[0]), reverse=True)

                self.images_cache = imgs
                self.images_cache_time = now

                return imgs

            def send_tar_file(self):
                """生成されたTARファイルをダウンロード"""
                with tar_generator.lock:
                    tar_path = tar_generator.tar_path

                if not tar_path or not os.path.exists(tar_path):
                    self.send_response(404)
                    self.send_header('Content-Type', 'text/plain; charset=utf-8')
                    self.end_headers()
                    self.wfile.write(b'TAR file not ready. Please try again.')
                    return

                try:
                    size = os.path.getsize(tar_path)
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/x-tar')
                    self.send_header('Content-Disposition', 'attachment; filename="comfyui_preview_gallery.tar"')
                    self.send_header('Content-Length', str(size))
                    self.end_headers()

                    # ストリーミング送信（メモリ節約）
                    with open(tar_path, 'rb') as f:
                        chunk_size = 64 * 1024
                        while True:
                            chunk = f.read(chunk_size)
                            if not chunk:
                                break
                            try:
                                self.wfile.write(chunk)
                            except BrokenPipeError:
                                break
                except Exception as e:
                    self.send_response(500)
                    self.send_header('Content-Type', 'text/plain; charset=utf-8')
                    self.end_headers()
                    self.wfile.write(f'Error: {str(e)}'.encode('utf-8'))

            def list_images_html(self, page=1):
                try:
                    files = [rel for (_, rel) in self.collect_all_images()]
                except Exception:
                    files = []

                total = len(files)
                page = max(1, min(page, max(1, math.ceil(total / PAGE_SIZE) if PAGE_SIZE > 0 else 1)))
                start = (page - 1) * PAGE_SIZE
                end = start + PAGE_SIZE
                page_files = files[start:end]

                imgs_html = "\n".join(
                    f'<a href="{file}" target="_blank"><img data-src="{file}" alt="{file}" class="lazy"></a>'
                    for file in page_files
                ) or "<p>No images found.</p>"

                total_pages = max(1, math.ceil(total / PAGE_SIZE)) if PAGE_SIZE > 0 else 1

                def page_link(p, text=None):
                    text = text or str(p)
                    return f'<a href="/?page={p}">{text}</a>'

                nav_parts = []
                if page > 1:
                    nav_parts.append(page_link(1, "First"))
                    nav_parts.append(page_link(page - 1, "Prev"))
                for p in range(max(1, page - 2), min(total_pages, page + 2) + 1):
                    if p == page:
                        nav_parts.append(f'<strong>{p}</strong>')
                    else:
                        nav_parts.append(page_link(p))
                if page < total_pages:
                    nav_parts.append(page_link(page + 1, "Next"))
                    nav_parts.append(page_link(total_pages, "Last"))
                nav_html = " | ".join(nav_parts) or ""

                # ダウンロードリンクを追加（生成済みTARをダウンロード）
                with tar_generator.lock:
                    is_generating = tar_generator.generating
                    has_tar = (
                        tar_generator.tar_path is not None
                        and os.path.exists(tar_generator.tar_path)
                    )

                if has_tar:
                    download_link = '<a href="/download.tar" style="margin-left:16px;">Download TAR</a>'
                elif is_generating:
                    download_link = '<span style="margin-left:16px;color:#666;">Generating TAR... (please wait)</span>'
                else:
                    download_link = '<a href="/request_make_tar" style="margin-left:16px;">Request TAR (prepare download)</a>'

                html = f"""<!doctype html>
<html lang="ja">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>ComfyUI Preview Gallery</title>
  <style>
    body{{font-family:system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial; padding:16px;}}
    .meta{{margin-bottom:8px;color:#666;}}
    .grid{{display:grid; grid-template-columns:repeat(auto-fill,minmax(180px,1fr)); gap:12px;}}
    .grid a{{display:block; overflow:hidden; border-radius:8px; background:#111; padding:4px;}}
    .grid img{{width:100%; height:180px; object-fit:cover; display:block; background:#222;}}
    .pager{{margin:12px 0;padding:8px;background:#f5f5f5;border-radius:6px;}}
    .pager a{{margin:0 6px;text-decoration:none;color:#06c;}}
    .pager strong{{margin:0 6px;}}
  </style>
</head>
<body>
  <h1>ComfyUI Preview Gallery</h1>
  <div class="meta">Total images: {total} — Page {page} / {total_pages}</div>
  <div class="meta">{download_link}</div>
  <div class="pager">{nav_html}</div>
  <div class="grid">
    {imgs_html}
  </div>
  <div class="pager">{nav_html}</div>
  <script>
    const lazyImgs = [].slice.call(document.querySelectorAll('img.lazy'));
    if ('IntersectionObserver' in window) {{
      let obs = new IntersectionObserver((entries, observer) => {{
        entries.forEach(entry => {{
          if (entry.isIntersecting) {{
            const img = entry.target;
            img.src = img.dataset.src;
            img.classList.remove('lazy');
            observer.unobserve(img);
          }}
        }});
      }}, {{rootMargin: '200px 0px'}});
      lazyImgs.forEach(img => obs.observe(img));
    }} else {{
      lazyImgs.forEach(img => img.src = img.dataset.src);
    }}
  </script>
</body>
</html>
"""
                return html

            def do_GET(self):
                parsed = urlparse(self.path)
                qs = parse_qs(parsed.query)
                page_vals = qs.get("page", [])
                try:
                    page = int(page_vals[0]) if page_vals else 1
                except Exception:
                    page = 1

                if parsed.path in ('/', '/index.html'):
                    content = self.list_images_html(page=page).encode('utf-8')
                    self.send_response(200)
                    self.send_header('Content-Type', 'text/html; charset=utf-8')
                    self.send_header('Content-Length', str(len(content)))
                    self.end_headers()
                    self.wfile.write(content)
                    return
                elif parsed.path in ['/favicon.ico', '/robots.txt']:
                    self.send_response(404)
                    self.end_headers()
                    return
                elif parsed.path == '/request_make_tar':
                    # TARファイル生成をリクエスト
                    imgs = self.collect_all_images()
                    request_make_tar(imgs)
                    # リダイレクトしてHTMLを再表示
                    self.send_response(302)
                    self.send_header('Location', '/')
                    self.end_headers()
                    return
                elif parsed.path == '/delete_tar':
                    # 既存のTARを削除して新規生成できるようにする
                    remove_tar()
                    # リダイレクトしてHTMLを再表示
                    self.send_response(302)
                    self.send_header('Location', '/')
                    self.end_headers()
                    return
                elif parsed.path == '/download.tar':
                    self.send_tar_file()
                    return

                self.path = parsed.path
                return super().do_GET()

        handler_factory = lambda *args, **kwargs: GalleryHTTPRequestHandler(*args, directory=self.directory, **kwargs)

        with socketserver.TCPServer(("0.0.0.0", self.port), handler_factory) as httpd:
            print(f"[Preview-Gallery] Serving '{self.directory}' at http://127.0.0.1:{self.port}")
            httpd.serve_forever()

def main():
    server = ThreadedHTTPServer(OUTPUT_DIR, PORT)
    server.start()
    try:
        server.join()
    except KeyboardInterrupt:
        print("\n[Preview-Gallery] Shutting down...")

if __name__ == "__main__":
    main()
