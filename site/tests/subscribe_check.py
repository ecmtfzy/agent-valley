# Get updates end to end against a fake Resend: ask, the mail (HTML and plain), the link, the button,
# forged and expired links, spacing per inbox, another site, bots, a full day, escaping, and a contact
# who left the list once coming back.
# Run from site/: python3 tests/subscribe_check.py
import io, json, os, re, sys, threading, time, urllib.error, urllib.parse, urllib.request
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'api'))
import subscribe as s
from http.server import HTTPServer
real = urllib.request.urlopen
mails, contacts, patches, quota = [], [], [], {'full': False}
known = {'exists': False, 'patch_fails': False}
class R:
    def __init__(self, body): self.status, self.body = 200, body
    def read(self): return self.body
    def __enter__(self): return self
    def __exit__(self, *a): pass
def fake(req, timeout=0):
    body = json.loads(req.data); assert req.headers['Authorization'] == 'Bearer re_test'
    if req.full_url.endswith('/emails'):
        if quota['full']: raise urllib.error.HTTPError(req.full_url, 429, 'x', {}, io.BytesIO(b'{"name":"daily_quota_exceeded"}'))
        mails.append(body); return R(b'{"id":"m"}')
    if req.get_method() == 'PATCH':
        patches.append((req.full_url, body))
        if known['patch_fails']: raise urllib.error.HTTPError(req.full_url, 500, 'x', {}, io.BytesIO(b'{}'))
        return R(b'{"id":"c"}')
    if known['exists']: raise urllib.error.HTTPError(req.full_url, 422, 'x', {}, io.BytesIO(b'{"message":"Contact already exists"}'))
    contacts.append(body); return R(b'{"id":"c"}')
s.urllib.request.urlopen = fake
os.environ['RESEND_API_KEY'] = 're_test'
srv = HTTPServer(('127.0.0.1', 0), s.handler); threading.Thread(target=srv.serve_forever, daemon=True).start()
base = f'http://127.0.0.1:{srv.server_port}'
def call(path, data=None, accept='application/json', site=None):
    h = {'Accept': accept, 'Content-Type': 'application/x-www-form-urlencoded'}
    if site: h['Sec-Fetch-Site'] = site
    r = urllib.request.Request(base + path, data=data.encode() if data is not None else None, headers=h, method='POST' if data is not None else 'GET')
    try: res = real(r); return res.status, res.read().decode()
    except urllib.error.HTTPError as e: return e.code, e.read().decode()
# 1. asking mails a link and adds nobody
st, b = call('/api/subscribe', 'email=reader%40example.com'); assert (st, json.loads(b)['said']) == (200, 'sent'), b
assert len(mails) == 1 and mails[0]['to'] == ['reader@example.com'] and contacts == []
link = re.search(r'https://agentvalley\.app(/api/subscribe\?\S+)', mails[0]['text']).group(1)
h = mails[0]['html']; assert '{{' not in h and 'this address' in h and 'Yes, send me updates' in h
assert ('href="https://agentvalley.app' + link.replace('&', '&amp;') + '"') in h, 'link in html'
assert "Say yes, and we'll write." in mails[0]['text'] and 'this address' in mails[0]['text']
# the address someone typed never reaches the words, only the link (encoded)
assert all('reader@example.com' not in mails[0][k] for k in ('text', 'html'))
# asking again soon sends no second mail
assert json.loads(call('/api/subscribe', 'email=reader%40example.com')[1])['said'] == 'sent' and len(mails) == 1
# the same inbox under another spelling is spaced out too
assert json.loads(call('/api/subscribe', 'email=Reader%40Example.com')[1])['said'] == 'sent' and len(mails) == 1
for v in ('reader%2Bx%40example.com', 'READER%2B2%40EXAMPLE.COM'):
    assert json.loads(call('/api/subscribe', 'email=' + v)[1])['said'] == 'sent'
assert len(mails) == 3 and mails[-1]['to'] == ['READER+2@EXAMPLE.COM'], mails
assert json.loads(call('/api/subscribe', 'email=reader%2B3%40example.com')[1])['said'] == 'failed' and len(mails) == 3
mails[1:] = []
# 2. the link shows a button, adds nobody
st, b = call(link, accept='text/html'); assert st == 200 and 'Yes, send me updates' in b and 'reader@example.com' in b and contacts == []
# forged and expired links
q = urllib.parse.parse_qs(urllib.parse.urlsplit(link).query)
forged = '/api/subscribe?' + urllib.parse.urlencode({'e': 'other@example.com', 'x': q['x'][0], 't': q['t'][0]})
assert call(forged, accept='text/html')[0] == 400
old = str(int(time.time()) - 5); expired = '/api/subscribe?' + urllib.parse.urlencode({'e': 'reader@example.com', 'x': old, 't': s.sign('reader@example.com', old)})
assert call(expired, accept='text/html')[0] == 400
# 3. the button adds the address
form = urllib.parse.urlencode({k: v[0] for k, v in q.items()})
st, b = call('/api/subscribe', form, accept='text/html', site='same-origin'); assert st == 200 and 'on the list. See you' in b and contacts[-1]['email'] == 'reader@example.com'
fq = urllib.parse.parse_qs(urllib.parse.urlsplit(forged).query)
st, b = call('/api/subscribe', urllib.parse.urlencode({k: v[0] for k, v in fq.items()}), accept='text/html'); assert st == 502 and 'run out' in b and len(contacts) == 1
# a yes always marks the contact subscribed again, in case they left the list once
assert patches[-1] == ('https://api.resend.com/contacts/reader@example.com', {'unsubscribed': False}), patches
# already a contact: the yes still counts, and puts them back on the list
known['exists'] = True; n = len(patches)
st, b = call('/api/subscribe', form, accept='text/html'); assert st == 200 and 'on the list. See you' in b and len(contacts) == 1 and len(patches) == n + 1
# already a contact, and Resend cannot put them back: say try again, not "on the list"
known['patch_fails'] = True
st, b = call('/api/subscribe', form, accept='text/html'); assert st == 502 and 'got away' in b
known.update(exists=False, patch_fails=False)
# another site, bots, bad addresses, a full day
assert json.loads(call('/api/subscribe', 'email=x%40example.com', site='cross-site')[1])['said'] == 'failed' and len(mails) == 1
assert json.loads(call('/api/subscribe', 'email=bot%40example.com&website=spam')[1])['said'] == 'sent' and len(mails) == 1
assert json.loads(call('/api/subscribe', 'email=nope')[1])['said'] == 'failed'
quota['full'] = True; assert json.loads(call('/api/subscribe', 'email=late%40example.com')[1])['said'] == 'full'
# escaping on the button page
quota['full'] = False; e = 'a"b<c@example.com'; x = str(int(time.time()) + 60)
st, b = call('/api/subscribe?' + urllib.parse.urlencode({'e': e, 'x': x, 't': s.sign(e, x)}), accept='text/html'); assert st == 200 and '<c@' not in b and '&quot;' in b
quota['full'] = False; n = len(mails); call('/api/subscribe', 'email=victim%2Bcall-555-refund%40example.com')
# their words ride only inside the link (the To line shows them anyway), never in the prose
words = re.sub(r'https://agentvalley\.app/api/subscribe\?[^"<\s]+', '', mails[-1]['html'] + mails[-1]['text'])
assert len(mails) == n + 1 and 'call-555-refund' not in words
s.LETTER = ''; call('/api/subscribe', 'email=plain%40example.com'); assert 'html' not in mails[-1] and 'text' in mails[-1]
print('confirm flow ok:', len(mails), 'mail,', len(contacts), 'contact')
