"""Get updates: one email address into Resend's contacts, for the mail we send with each new version.

POST /api/subscribe with `email`, as a form (application/x-www-form-urlencoded). The page's script
asks for JSON and shows the answer by the box; a form sent without scripts gets a small page back.
A filled `website` field is a bot: thanked, and dropped. Needs RESEND_API_KEY (a full-access key)
in the Vercel project; RESEND_SEGMENT_ID, if set, puts each address in that segment too.
"""

import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler

EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")

IN = "You're on the list. See you at the next version."
FAILED = "That one got away from us. Try again in a minute."


def add(email: str) -> bool:
    body = {"email": email, "unsubscribed": False}
    if os.environ.get("RESEND_SEGMENT_ID"):
        body["segments"] = [{"id": os.environ["RESEND_SEGMENT_ID"]}]
    request = urllib.request.Request(
        "https://api.resend.com/contacts",
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {os.environ['RESEND_API_KEY']}",
            "Content-Type": "application/json",
            "User-Agent": "agentvalley.app",
        },
        method="POST",
    )
    try:
        urllib.request.urlopen(request, timeout=8)
        return True
    except urllib.error.HTTPError as error:
        # Already on the list counts as on the list.
        return "already exist" in error.read().decode(errors="replace").lower()
    except (urllib.error.URLError, TimeoutError):
        return False


class handler(BaseHTTPRequestHandler):
    def do_POST(self):
        size = int(self.headers.get("Content-Length") or 0)
        form = urllib.parse.parse_qs(self.rfile.read(min(size, 2048)).decode(errors="replace"))
        email = (form.get("email") or [""])[0].strip()
        if self.headers.get("Sec-Fetch-Site", "same-origin") != "same-origin":
            # Another site's page cannot sign its visitors up; browsers say where a post comes from.
            ok = False
        elif form.get("website", [""])[0]:
            ok = True
        elif len(email) > 254 or not EMAIL.match(email) or "RESEND_API_KEY" not in os.environ:
            ok = False
        else:
            ok = add(email)
        if "application/json" in (self.headers.get("Accept") or ""):
            self.answer(200 if ok else 502, "application/json", json.dumps({"ok": ok}))
        else:
            words = IN if ok else FAILED
            page = f'<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Get updates · AgentValley</title><p>{words}</p><p><a href="/#updates">Back to AgentValley</a></p>'
            self.answer(200 if ok else 502, "text/html; charset=utf-8", page)

    def answer(self, status: int, kind: str, text: str):
        data = text.encode()
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)
