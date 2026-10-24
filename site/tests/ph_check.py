# The Product Hunt badge: their SVG passes through with a minute's cache; a failure or a page that
# isn't an SVG sends the countless badge instead.
# Run from site/: python3 tests/ph_check.py
import os, sys, threading, urllib.error, urllib.request
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'api'))
import ph
from http.server import HTTPServer
real = urllib.request.urlopen
answer = {'body': b'<?xml version="1.0"?>\n<svg><tspan>99</tspan></svg>', 'fail': False}
class R:
    def __init__(self, body): self.body = body
    def read(self, n=-1): return self.body
    def __enter__(self): return self
    def __exit__(self, *a): pass
def fake(url, timeout=0):
    assert url.startswith(ph.BADGE + '&t='), url
    if answer['fail']: raise urllib.error.URLError('down')
    return R(answer['body'])
ph.urllib.request.urlopen = fake
srv = HTTPServer(('127.0.0.1', 0), ph.handler); threading.Thread(target=srv.serve_forever, daemon=True).start()
class Stay(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a): return None
get = urllib.request.build_opener(Stay).open
def call():
    try: r = get(f'http://127.0.0.1:{srv.server_port}/api/ph'); return r.status, r.headers, r.read()
    except urllib.error.HTTPError as e: return e.code, e.headers, e.read()
st, h, b = call()
assert st == 200 and b'99' in b and h['Content-Type'] == 'image/svg+xml' and 's-maxage=60' in h['Cache-Control']
assert 'sandbox' in h['Content-Security-Policy']
answer['body'] = b'<html>Just a moment...</html>'
st, h, _ = call(); assert st == 302 and h['Location'] == '/product-hunt.svg', st
answer['fail'] = True
st, h, _ = call(); assert st == 302 and h['Location'] == '/product-hunt.svg', st
srv.shutdown()
print('ph ok')
