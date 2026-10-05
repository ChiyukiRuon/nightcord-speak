// This surface must work before Flutter, CanvasKit and application code load.
(() => {
  const root = document.getElementById('startup');
  const message = document.getElementById('startup-message');
  const retry = document.getElementById('startup-retry');
  const chinese = (navigator.language || '').startsWith('zh');
  let complete = false;
  let failed = false;
  let stage = 'resources';
  const labels = chinese
    ? { resources: '正在加载应用资源…', renderer: '正在初始化渲染器…', app: '正在启动应用…' }
    : { resources: 'Loading application resources…', renderer: 'Initializing renderer…', app: 'Starting application…' };
  function update(next) {
    stage = next;
    if (!complete && !failed) message.textContent = labels[next] || labels.resources;
  }
  function fail() {
    if (complete) return;
    failed = true;
    root.setAttribute('role', 'alert');
    message.textContent = chinese
      ? `应用启动失败（${stage}）。请重新加载；如果仍失败，请提供页面地址、浏览器与系统版本，以及这个阶段名称。`
      : `Application startup failed (${stage}). Reload, or report the page URL, browser and OS versions, and this stage.`;
    retry.hidden = false;
  }
  const timer = setTimeout(() => {
    if (!complete && !failed) {
      message.textContent = chinese
        ? `启动仍未完成（${stage}）。首次加载需要下载渲染资源，请检查网络；也可以重新加载。`
        : `Startup is still pending (${stage}). The first visit downloads renderer assets. Check your connection or reload.`;
      retry.hidden = false;
    }
  }, 30000);
  retry.addEventListener('click', () => location.reload());
  window.addEventListener('flutter-first-frame', () => {
    complete = true;
    clearTimeout(timer);
    root.remove();
  }, { once: true });
  window.addEventListener('error', event => {
    if (event.target instanceof HTMLScriptElement || event.error) fail();
  }, true);
  window.addEventListener('unhandledrejection', fail);
  window.NightcordStartup = { update, fail };
  update(stage);
})();
