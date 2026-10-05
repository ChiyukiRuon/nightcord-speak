const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

function startup() {
  const root = { role: 'status', removed: false,
    setAttribute(_, value) { this.role = value; },
    remove() { this.removed = true; } };
  const message = { textContent: '' };
  const retry = { hidden: true, addEventListener() {} };
  const elements = { startup: root, 'startup-message': message, 'startup-retry': retry };
  const listeners = new Map();
  let delayed;
  let cancelled = false;
  class Script {}
  const window = { addEventListener(name, handler) { listeners.set(name, handler); } };
  const context = vm.createContext({
    window, navigator: { language: 'en-US' }, HTMLScriptElement: Script,
    document: { getElementById: id => elements[id] }, location: { reload() {} },
    setTimeout(callback) { delayed = callback; return 1; },
    clearTimeout() { cancelled = true; },
  });
  vm.runInContext(fs.readFileSync(path.join(__dirname, '../web/startup.js'), 'utf8'), context);
  return { root, message, retry, window, Script,
    emit: (name, event = {}) => listeners.get(name)(event),
    timeout: () => delayed(), cancelled: () => cancelled };
}

test('a failed script presents a useful screen before Flutter can draw', () => {
  // Previously a missing bootstrap or application script left a blank page.
  const app = startup();
  app.emit('error', { target: new app.Script() });
  assert.equal(app.root.role, 'alert');
  assert.equal(app.retry.hidden, false);
  assert.match(app.message.textContent, /startup failed \(resources\)/);
});

test('renderer rejection reports its stage without exposing error contents', () => {
  const app = startup();
  app.window.NightcordStartup.update('renderer');
  app.emit('unhandledrejection', { reason: 'private gateway token' });
  assert.match(app.message.textContent, /\(renderer\)/);
  assert.ok(!app.message.textContent.includes('private gateway token'));
});

test('slow downloads stay visible and can be retried', () => {
  const app = startup();
  app.timeout();
  assert.match(app.message.textContent, /still pending/);
  assert.equal(app.retry.hidden, false);
});

test('the first Flutter frame removes the loading screen permanently', () => {
  const app = startup();
  app.emit('flutter-first-frame');
  assert.equal(app.root.removed, true);
  assert.equal(app.cancelled(), true);
  app.emit('unhandledrejection', { reason: 'an unrelated later failure' });
  assert.equal(app.root.role, 'status');
});

test('bootstrap catches engine failure instead of leaving an empty page', async () => {
  let options;
  let stage;
  let failed = false;
  const context = vm.createContext({
    _flutter: { loader: { load(value) { options = value; return Promise.resolve(); } } },
    window: { NightcordStartup: { update(value) { stage = value; }, fail() { failed = true; } } },
    console: { error() {} },
  });
  const bootstrap = fs.readFileSync(path.join(__dirname, '../web/flutter_bootstrap.js'), 'utf8')
    .replace('{{flutter_js}}', '').replace('{{flutter_build_config}}', '');
  vm.runInContext(bootstrap, context);
  await options.onEntrypointLoaded({ initializeEngine() { return Promise.reject(new Error('missing wasm')); } });
  assert.equal(stage, 'renderer');
  assert.equal(failed, true);
});
