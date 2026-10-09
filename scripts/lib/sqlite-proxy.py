#!/usr/bin/env python3
"""
本地 SQLite 代理服务器
为 sqlite3 原生资产的 hook 下载请求提供本地缓存服务。
Dart 的 HttpClient 在 HTTPS_PROXY 指向本机时，会通过 CONNECT 隧道请求。
但更简单的方式：直接响应 HTTP 请求，用 path 匹配本地缓存文件。

用法（由 setup_sqlite_cache.sh 自动管理，无需手动调用）：
  python3 scripts/lib/sqlite-proxy.py <port> <cache-dir>
"""

import http.server
import os
import sys
import urllib.parse

# 需要拦截的 URL 路径前缀
TARGET_PREFIX = "/simolus3/sqlite3.dart/releases/download/sqlite3-3.1.0/"


class CacheHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        # 只处理 sqlite3 的下载请求
        if not path.startswith(TARGET_PREFIX):
            self.send_error(404, f"Not cached: {path}")
            return

        filename = path[len(TARGET_PREFIX):]
        if not filename:
            self.send_error(400, "Missing filename")
            return

        # 在缓存目录中查找文件
        cache_path = os.path.join(self.server.cache_dir, filename)
        if not os.path.isfile(cache_path):
            self.send_error(404, f"Not in cache: {filename}")
            return

        file_size = os.path.getsize(cache_path)
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(file_size))
        self.end_headers()

        with open(cache_path, "rb") as f:
            self.wfile.write(f.read())

    def do_CONNECT(self):
        """处理 HTTPS CONNECT 隧道请求——不代理，直接拒绝。
        但 Dart HttpClient 会先尝试 CONNECT，失败后可能回退到 HTTP。"""
        self.send_response(405, "Method Not Allowed")
        self.end_headers()

    def log_message(self, format, *args):
        if "sqlite3" in str(args):
            print(f"  [proxy] {args[0]} {args[1]} - {args[2]}")


class Server(http.server.HTTPServer):
    def __init__(self, addr, handler, cache_dir):
        self.cache_dir = cache_dir
        super().__init__(addr, handler)


def main():
    if len(sys.argv) < 3:
        print(f"用法: {sys.argv[0]} <port> <cache-dir>")
        sys.exit(1)

    port = int(sys.argv[1])
    cache_dir = os.path.abspath(sys.argv[2])

    if not os.path.isdir(cache_dir):
        print(f"缓存目录不存在: {cache_dir}")
        sys.exit(1)

    # 检查缓存文件
    expected = [
        f"libsqlite3.arm64.macos.dylib",
        f"libsqlite3.x64.macos.dylib",
    ]
    for f in expected:
        path = os.path.join(cache_dir, f)
        if not os.path.isfile(path):
            print(f"⚠ 缓存文件缺失: {f}")

    server = Server(("127.0.0.1", port), CacheHandler, cache_dir)
    print(f"SQLite 本地代理运行在 http://127.0.0.1:{port}")
    print(f"缓存目录: {cache_dir}")
    print(f"按 Ctrl+C 停止")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()


if __name__ == "__main__":
    main()
