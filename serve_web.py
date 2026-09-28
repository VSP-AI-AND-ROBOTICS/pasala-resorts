import http.server
import socketserver
import os

PORT = 8080
DIRECTORY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build", "web")

class SPAHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def do_GET(self):
        path = self.translate_path(self.path)
        # If the requested path is not an existing file, fallback to index.html for client-side routing
        if not os.path.exists(path):
            self.path = "/index.html"
        elif os.path.isdir(path):
            index_in_dir = os.path.join(path, "index.html")
            if not os.path.exists(index_in_dir):
                self.path = "/index.html"
        return super().do_GET()

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        super().end_headers()

socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("127.0.0.1", PORT), SPAHandler) as httpd:
    print(f"Serving Flutter app at http://127.0.0.1:{PORT}", flush=True)
    httpd.serve_forever()
