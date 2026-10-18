import { defineConfig } from '@playwright/test';

// The tests read the built site in out/, served as plain files, the way a host would serve it.
// Python's file server queues only 5 connections by default; Chrome asks for more at once and the
// rest are reset, so a script never arrives. The queue is raised to 128.
const SERVE =
  "python3 -c \"import functools,http.server as h; h.ThreadingHTTPServer.request_queue_size=128; " +
  "h.test(HandlerClass=functools.partial(h.SimpleHTTPRequestHandler,directory='out'),ServerClass=h.ThreadingHTTPServer,port=4321,bind='127.0.0.1')\"";
// HALLOWEEN=1 runs every test with the Halloween decorations forced on, as ?halloween leaves them.
const HALLOWEEN = process.env.HALLOWEEN === '1'
  ? { cookies: [], origins: [{ origin: 'http://127.0.0.1:4321', localStorage: [{ name: 'halloween', value: '1' }] }] }
  : undefined;
export default defineConfig({
  testDir: 'e2e',
  fullyParallel: true,
  reporter: 'list',
  use: { baseURL: 'http://127.0.0.1:4321', channel: 'chrome', storageState: HALLOWEEN },
  webServer: {
    command: SERVE,
    url: 'http://127.0.0.1:4321',
    reuseExistingServer: !process.env.CI,
    stderr: 'ignore',
  },
});
