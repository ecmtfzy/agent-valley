"""Get updates, with a yes from the mailbox before anyone is on the list.

1. POST `email` (a form, application/x-www-form-urlencoded): we mail a link to that address and add
   nothing yet. The page's script asks for JSON and shows the answer by the box; a form sent without
   scripts gets a small page back. A filled `website` field is a bot: thanked, and dropped.
2. GET the link (?e=&x=&t=): a page with one button. A button, not the link itself, because some mail
   scanners open every link they see.
3. POST the button (e, x, t): the address goes into Resend's contacts.

The link carries its own proof: an HMAC of the address and its expiry, keyed from RESEND_API_KEY, so
nothing waits anywhere between 1 and 3. Needs RESEND_API_KEY (full access) in the Vercel project;
RESEND_SEGMENT_ID, if set, puts each address in that segment too. A Vercel Firewall rule limits each
IP on this path; this file only spaces out the mail to one address.
"""

import hashlib
import hmac
import html
import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler

EMAIL = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
SITE = "https://agentvalley.app"
DAYS = 7
# ponytail: per-instance memory, so a second instance may mail the same inbox again; the Firewall
# rule on this path is the real limit, a shared store if that ever falls short. An address is mailed
# at most once per SPACING, an inbox (all its spellings) at most PER_BOX times.
SENT: dict[str, float] = {}
BOXES: dict[str, list[float]] = {}
SPACING = 600
PER_BOX = 3

SAID = {
    "sent": "Check your inbox. One click there and you're on the list.",
    "full": "We've sent all the mail we can for today. Try again tomorrow.",
    "failed": "That one got away from us. Try again in a minute.",
    "ask": "One more press and you're on the list.",
    "in": "You're on the list. See you at the next version.",
    "old": "That link has run out. Ask again on the page and we'll send a fresh one.",
}

MAIL = """Someone, hopefully you, asked for AgentValley news at this address.

To say yes, open this link and press the button:
{link}

The link works for {days} days. If it wasn't you, do nothing: we won't write again.

The crew in your notch
https://agentvalley.app
"""


def resend(path: str, body: dict) -> tuple[int, str]:
    request = urllib.request.Request(
        f"https://api.resend.com{path}",
        data=json.dumps(body).encode(),
        headers={
            "Authorization": f"Bearer {os.environ['RESEND_API_KEY']}",
            "Content-Type": "application/json",
            "User-Agent": "agentvalley.app",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            return response.status, response.read().decode(errors="replace")
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode(errors="replace")
    except (urllib.error.URLError, TimeoutError):
        return 0, ""


def sign(email: str, expiry: str) -> str:
    key = hashlib.sha256(b"agentvalley confirm\n" + os.environ["RESEND_API_KEY"].encode()).digest()
    return hmac.new(key, f"{email}\n{expiry}".encode(), hashlib.sha256).hexdigest()


def proven(fields: dict) -> str | None:
    """The address a link vouches for, or None when it is forged, broken or past its days."""
    email, expiry, token = (fields.get(k, [""])[0] for k in ("e", "x", "t"))
    if not (email and expiry.isdigit() and token) or int(expiry) < time.time():
        return None
    return email if hmac.compare_digest(sign(email, expiry), token) else None


def mailbox(email: str) -> str:
    """One key per inbox: Reader+1@Example.com and reader@example.com are one."""
    name, _, domain = email.lower().rpartition("@")
    return f"{name.split('+')[0]}@{domain}"


def ask(email: str) -> str:
    """Mails the link. Returns sent, full (the plan's mail for the day is gone) or failed."""
    now, exact, box = time.time(), email.lower(), mailbox(email)
    if now - SENT.get(exact, 0) < SPACING:
        # This very address has a fresh link.
        return "sent"
    recent = [t for t in BOXES.get(box, []) if now - t < SPACING]
    if len(recent) >= PER_BOX:
        # Spellings of one inbox (case, +tags) cannot fill it with mail.
        return "failed"
    expiry = str(int(time.time()) + DAYS * 86400)
    link = f"{SITE}/api/subscribe?" + urllib.parse.urlencode({"e": email, "x": expiry, "t": sign(email, expiry)})
    status, body = resend("/emails", {
        "from": "AgentValley <hello@agentvalley.app>",
        "to": [email],
        "subject": "Confirm your AgentValley updates",
        "text": MAIL.format(link=link, days=DAYS),
    })
    if 200 <= status < 300:
        SENT[exact] = now
        BOXES[box] = recent + [now]
        return "sent"
    return "full" if "quota" in body else "failed"


def add(email: str) -> bool:
    body = {"email": email, "unsubscribed": False}
    if os.environ.get("RESEND_SEGMENT_ID"):
        body["segments"] = [{"id": os.environ["RESEND_SEGMENT_ID"]}]
    status, answer = resend("/contacts", body)
    # Already on the list counts as on the list.
    return 200 <= status < 300 or "already exist" in answer.lower()


def page(words: str, form: str = "") -> str:
    return f"""<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Get updates · AgentValley</title>
<style>body{{margin:0;min-height:100vh;display:grid;place-items:center;background:#f9f8f4;color:#1a1915;font:17px/1.6 ui-monospace,SFMono-Regular,Menlo,monospace}}main{{max-width:30rem;padding:24px 16px}}button{{min-height:48px;padding:0 20px;border:0;border-radius:8px;background:#1a1915;color:#f9f8f4;font:600 1rem ui-monospace,Menlo,monospace;cursor:pointer}}a{{color:#7a3d00}}:focus-visible{{outline:2px solid #7a3d00;outline-offset:3px}}</style>
<main><p>{html.escape(words)}</p>{form}<p><a href="/#updates">Back to AgentValley</a></p></main></html>"""


class handler(BaseHTTPRequestHandler):
    def do_GET(self):
        fields = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
        email = proven(fields) if "RESEND_API_KEY" in os.environ else None
        if not email:
            return self.answer(400, "text/html; charset=utf-8", page(SAID["old"]))
        hidden = "".join(f'<input type="hidden" name="{k}" value="{html.escape(fields[k][0])}">' for k in ("e", "x", "t"))
        button = f'<form method="post" action="/api/subscribe">{hidden}<button type="submit">Yes, send me updates</button></form>'
        self.answer(200, "text/html; charset=utf-8", page(f"{SAID['ask']} ({email})", button))

    def do_POST(self):
        size = int(self.headers.get("Content-Length") or 0)
        fields = urllib.parse.parse_qs(self.rfile.read(min(size, 2048)).decode(errors="replace"))
        email = (fields.get("email") or [""])[0].strip()
        ready = "RESEND_API_KEY" in os.environ
        if self.headers.get("Sec-Fetch-Site", "same-origin") != "same-origin":
            # Another site's page cannot sign its visitors up; browsers say where a post comes from.
            said = "failed"
        elif "t" in fields:
            # The button on the link's page.
            confirmed = proven(fields) if ready else None
            said = "in" if confirmed and add(confirmed) else "old" if ready and not confirmed else "failed"
        elif fields.get("website", [""])[0]:
            said = "sent"
        elif len(email) > 254 or not EMAIL.match(email) or not ready:
            said = "failed"
        else:
            said = ask(email)
        ok = said in ("sent", "in")
        if "application/json" in (self.headers.get("Accept") or ""):
            self.answer(200 if ok else 502, "application/json", json.dumps({"ok": ok, "said": said}))
        else:
            self.answer(200 if ok else 502, "text/html; charset=utf-8", page(SAID[said]))

    def answer(self, status: int, kind: str, text: str):
        data = text.encode()
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        self.wfile.write(data)
