"""Product Hunt's badge with the live vote count, served from our own address: the page loads
images from us only (vercel.json). Vercel's edge keeps each answer a minute, so Product Hunt sees
about one call a minute however many people read the page. If they don't answer, the badge
without a count (public/product-hunt.svg) stands in.
"""

import time
import urllib.request
from http.server import BaseHTTPRequestHandler

# AgentValley's launch, 24 Oct 2026.
BADGE = "https://api.producthunt.com/widgets/embed-image/v1/featured.svg?post_id=1286641&theme=light"
# Their own embed code adds t; a new one each minute steps past their four-hour cache.
CACHE = "public, max-age=60, s-maxage=60, stale-while-revalidate=600"


def fetch() -> bytes | None:
    try:
        with urllib.request.urlopen(f"{BADGE}&t={int(time.time()) // 60}", timeout=5) as r:
            data = r.read(32_000)
    except Exception:
        return None
    return data if b"<svg" in data[:300] else None


class handler(BaseHTTPRequestHandler):
    def do_GET(self):
        data = fetch()
        if data is None:
            self.send_response(302)
            self.send_header("Location", "/product-hunt.svg")
            self.send_header("Cache-Control", "public, max-age=60, s-maxage=60")
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "image/svg+xml")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", CACHE)
        # Someone else's SVG on our address: opened on its own, it may run nothing.
        self.send_header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; sandbox")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(data)
