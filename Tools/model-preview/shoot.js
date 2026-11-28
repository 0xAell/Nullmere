// Draws a sheet of models in headless Chromium and saves it as a PNG.
//   node Tools/model-preview/shoot.js <models.json> <out.png> [query]
// Needs Playwright with Chromium (as on CI's Linux runners and in cloud sessions).
const { chromium } = require('playwright');
const http = require('http');
const fs = require('fs');
const path = require('path');
const [data, out, query] = process.argv.slice(2);
const assets = new Map([
  ['/index.html', [path.join(__dirname, 'index.html'), 'text/html']],
  ['/models.json', [path.resolve(data), 'application/json']],
]);
const server = http.createServer((req, res) => {
  const asset = assets.get(req.url.split('?', 1)[0]);
  if (!asset) { res.statusCode = 404; res.end(); return; }
  const [file, contentType] = asset;
  fs.readFile(file, (err, body) => {
    if (err) { res.statusCode = 404; res.end(); return; }
    res.setHeader('Content-Type', contentType);
    res.end(body);
  });
});
server.listen(0, '127.0.0.1', async () => {
  const port = server.address().port;
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 1400, height: 900 } });
  page.on('pageerror', (e) => console.log('pageerror:', e.message));
  await page.goto(`http://127.0.0.1:${port}/index.html?data=/models.json&${query || ''}`);
  await page.waitForFunction(() => document.title === 'ready' || document.getElementById('error').textContent, null, { timeout: 120000 });
  const error = await page.textContent('#error');
  if (error) { console.log('error:', error); process.exitCode = 1; }
  await page.screenshot({ path: out, fullPage: true });
  await browser.close();
  server.close();
});
