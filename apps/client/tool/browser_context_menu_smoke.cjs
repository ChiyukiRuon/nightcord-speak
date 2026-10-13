// Run against a built preview; optionally set PLAYWRIGHT_MODULE to a local install.
const assert = require('node:assert/strict');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

(async () => {
  const browser = await chromium.launch({headless: true});
  let page;
  try {
    page = await browser.newPage({viewport: {width: 1400, height: 1000}});
    await page.addInitScript(() => {
      window.__contextMenus = [];
      window.__frames = [];
      window.addEventListener('contextmenu', event => {
        setTimeout(() => window.__contextMenus.push(event.defaultPrevented), 0);
      }, true);
      const Base = window.WebSocket;
      window.WebSocket = class extends Base {
        constructor(...args) {
          super(...args);
          window.__socket = this;
          this.addEventListener('message', event => {
            if (typeof event.data === 'string') window.__frames.push(JSON.parse(event.data));
          });
        }
      };
    });
    await page.goto(process.env.WEB_PREVIEW_URL || 'http://localhost:5173/');
    await page.waitForFunction(() => window.__frames.some(frame => frame.kind === 'welcome'));
    await page.locator('flt-semantics-placeholder').evaluate(element => element.click());
    // Ordinary clicks retain the browser menu; only app actions suppress it.
    await page.mouse.click(1200, 900, {button: 'right'});
    await page.waitForFunction(() => window.__contextMenus.length > 0);
    assert.equal(await page.evaluate(() => window.__contextMenus.at(-1)), false);
    await page.keyboard.press('Escape');
    await page.evaluate(address => window.__socket.send(JSON.stringify({
      command: 'connect', payload: {address, nickname: 'Web context menu diagnostic', protocol: 'ts6'},
    })), process.env.TS_SERVER || '192.168.31.128:9988');
    await page.waitForFunction(() => window.__frames.some(frame => frame.event?.event === 'own_client_identified'));
    const member = page.getByRole('button', {name: /Actions for|的操作/}).first();
    const bounds = await member.boundingBox();
    const point = {x: bounds.x + bounds.width / 2, y: bounds.y + bounds.height / 2};
    // Real users hit the Flutter surface without the accessibility overlay.
    await page.addStyleTag({content: 'flt-semantics-host, flt-semantics-host * { pointer-events: none !important; }'});
    await page.mouse.move(point.x, point.y);
    await page.mouse.down({button: 'right'});
    await page.waitForTimeout(500);
    await page.waitForFunction(() => document.querySelector('[aria-label="Poke"], [aria-label="戳一戳"]'));
    // Windows can deliver contextmenu on release, after the popup covers the row.
    const latePrevented = await page.evaluate(point => {
      const event = new MouseEvent('contextmenu', {bubbles: true, cancelable: true, button: 2, clientX: point.x, clientY: point.y});
      document.elementFromPoint(point.x, point.y).dispatchEvent(event);
      return event.defaultPrevented;
    }, point);
    await page.mouse.up({button: 'right'});
    assert.equal(latePrevented, true, 'menu opened before the DOM contextmenu event must still suppress the browser menu');
    await page.keyboard.press('Escape');
    const before = await page.evaluate(() => window.__contextMenus.length);
    await page.mouse.click(1200, 900, {button: 'right'});
    await page.waitForFunction(before => window.__contextMenus.length > before, before);
    assert.equal(await page.evaluate(() => window.__contextMenus.at(-1)), false);
    await page.keyboard.press('Escape');
    console.log('PASS: app member actions suppress the browser menu; ordinary areas retain it before and after app menus.');
  } finally {
    if (page) {
      await page.evaluate(() => {
        const own = window.__frames?.find(frame => frame.event?.event === 'own_client_identified');
        if (own) window.__socket.send(JSON.stringify({command: 'disconnect', payload: {session: own.session}}));
      }).catch(() => {});
    }
    await browser.close();
  }
})().catch(error => {console.error(error); process.exitCode = 1;});
