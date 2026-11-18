#!/usr/bin/env python3
"""Serves engines/dist on 127.0.0.1 for serve-packs.sh and the tests. Only data files, as the app only ever downloads
those: anything with a program extension (js, mjs, wasm, txt, json, the same rule as PackFiles in
ios/ZeistChess/Engines/Packs.swift) is answered 404, catalog.json and manifests too. The app's engines, their
programs and manifests come from the app itself."""
import http.server, os, sys

PORT, ROOT = int(sys.argv[1]), os.path.abspath(sys.argv[2])
PROGRAM = {"js", "mjs", "wasm", "txt", "json"}


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=ROOT, **k)

    def send_head(self):
        path = self.path.split('?')[0]
        ext = os.path.splitext(path)[1].lstrip('.').lower()
        if path.endswith('/') or ext in PROGRAM:
            self.send_error(404)
            return None
        return super().send_head()

    def log_message(self, *a):
        pass


http.server.ThreadingHTTPServer(('127.0.0.1', PORT), Handler).serve_forever()
