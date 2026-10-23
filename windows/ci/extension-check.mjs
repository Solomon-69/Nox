// Loads the real Nox Chrome extension into Chromium on the Windows machine and shows a light page
// (a Gmail-like inbox) with the PC light, then with the PC dark. Screenshots show the page going dark.
import { chromium } from 'playwright';
import path from 'node:path';
import fs from 'node:fs';
import http from 'node:http';
const ext = path.resolve('ChromeExtension');
const out = path.resolve(process.argv[2] || 'shots');
fs.mkdirSync(out, { recursive: true });
const html = `<html><body style="margin:0;font:16px Arial;background:#fff;color:#202124">
<div style="padding:16px;border-bottom:1px solid #ddd"><b style="color:#d93025;font-size:22px">Gmail</b> &nbsp; Search mail</div>
${[1,2,3,4,5,6].map(i=>`<div style="padding:14px 16px;border-bottom:1px solid #eee;background:${i%2?'#fff':'#f6f8fc'}"><b>Sender ${i}</b> &nbsp; Subject line number ${i} - preview text of the message</div>`).join('')}
</body></html>`;
const server = http.createServer((q, r) => { r.setHeader('content-type', 'text/html'); r.end(html); }).listen(8765);
const dir = fs.mkdtempSync(path.join(process.env.TEMP || '.', 'pw-'));
const ctx = await chromium.launchPersistentContext(dir, {
  headless: false, channel: 'chromium', colorScheme: 'light',
  args: [`--disable-extensions-except=${ext}`, `--load-extension=${ext}`],
});
const page = await ctx.newPage();
await page.goto('http://127.0.0.1:8765/');
await page.waitForTimeout(1500);
await page.screenshot({ path: path.join(out, '10-web-light.png') });
await page.emulateMedia({ colorScheme: 'dark' });   // what Chrome does when Windows turns dark
await page.waitForTimeout(2500);
await page.screenshot({ path: path.join(out, '10-web-dark.png') });
const bg = await page.evaluate(() => getComputedStyle(document.documentElement).filter);
console.log('html filter with PC dark:', bg);
await ctx.close(); server.close();
if (!/invert/.test(bg)) { console.error('FAIL: page was not darkened'); process.exit(1); }
console.log('PASS: extension darkened the page');
