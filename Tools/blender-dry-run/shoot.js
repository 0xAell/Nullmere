// Draws the meshes Tools/blender-dry-run/run.py wrote, each level of a work
// side by side, in headless Chromium with three.js, and saves a PNG; prints
// each level's triangles, how far it reaches from its foot and how high.
//   npm install --no-save --prefix Tools/blender-dry-run three@0.160.0
//   node Tools/blender-dry-run/shoot.js <model.json> <out.png> [query]
// The query: variants=1,2,3 (the tags to draw), near=0 (far pieces only),
// yaw, tilt and dist (the camera about the work), scale (0.1, Blender's
// tenth).
const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const [data, out, query] = process.argv.slice(2);
const root = __dirname;
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split('?')[0]);
  const file = url === '/model.json' ? path.resolve(data) : path.join(root, url);
  fs.readFile(file, (err, body) => {
    if (err) { res.statusCode = 404; res.end(); return; }
    res.setHeader('Content-Type', file.endsWith('.html') ? 'text/html' : file.endsWith('.js') ? 'text/javascript' : 'application/json');
    res.end(body);
  });
});
server.listen(0, async () => {
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
  const page = await browser.newPage({ viewport: { width: 1500, height: 360 } });
  page.on('pageerror', e => console.log('pageerror:', e.message));
  page.on('console', m => { if (m.type() === 'error') console.log('console:', m.text()); });
  await page.goto(`http://127.0.0.1:${server.address().port}/view.html?data=/model.json&${query || ''}`);
  await page.waitForFunction(() => document.title === 'ready', null, { timeout: 120000 });
  console.log((await page.evaluate(() => window.stats)).join('\n'));
  await page.locator('canvas').screenshot({ path: out });
  await browser.close(); server.close();
});
