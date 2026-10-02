'use strict';

const $ = (id) => document.getElementById(id);
let csrf;
let current;
let timer;
let fetching = false;
let displayedPlan;
let accountsKey;
let regionsReady = false;
const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
const stateLabels = { pending: '尚未開始', running: '處理中', complete: '已完成', failed: '需要處理', paused: '已停止', waiting: '待本人操作', skipped: '已是最新，略過' };
// Long steps say so up front; the elapsed time shows the wizard is still alive.
const slowSteps = { 'google-project': '可能需要數分鐘', firebase: '可能需要數分鐘', build: '可能需要十幾分鐘', publish: '可能需要幾分鐘' };
let installsKey;
let updateKey;
const runningSince = new Map();
// Google is still working (or may have accepted a request): resume later, do not redo.
const laterCodes = new Set(['GOOGLE_OPERATION_PENDING', 'GOOGLE_REQUEST_UNCONFIRMED', 'GOOGLE_API_PROPAGATING', 'GOOGLE_RATE_LIMITED']);
let busySince;

function elapsed(since) {
  const seconds = Math.floor((Date.now() - since) / 1000);
  return seconds < 60 ? `${seconds} 秒` : `${Math.floor(seconds / 60)} 分 ${seconds % 60} 秒`;
}

async function request(route, body) {
  const headers = { 'X-Installer-Request': '1' };
  if (body !== undefined) {
    headers['Content-Type'] = 'application/json';
    if (csrf) headers['X-Installer-CSRF'] = csrf;
  }
  const response = await fetch(route, {
    method: body === undefined ? 'GET' : 'POST', headers,
    body: body === undefined ? undefined : JSON.stringify(body), credentials: 'same-origin', cache: 'no-store',
  });
  const result = await response.json();
  if (!response.ok) throw Object.assign(new Error(result.message ?? '操作未完成'), { status: response.status, action: result.action });
  return result;
}

function showError(error) {
  $('error-box').hidden = !error;
  $('error-message').textContent = error?.message ?? '';
  $('error-action').hidden = true;
  $('error-action').removeAttribute('href');
  if (error?.action?.url) {
    const url = new URL(error.action.url);
    if (url.protocol === 'https:' && ['console.firebase.google.com', 'console.cloud.google.com', 'dash.cloudflare.com'].includes(url.hostname)) {
      $('error-action').href = url.href;
      $('error-action').textContent = error.action.title ?? '開啟官方設定頁';
      $('error-action').hidden = false;
    }
  }
}

async function perform(action) {
  try { showError(); await action(); await refresh(); }
  catch (error) { showError(error); }
}

function addService({ label = '', name = '', weekday = 7 } = {}) {
  if ($('services').children.length >= 20) return;
  const row = document.createElement('div');
  row.className = 'service-row';
  for (const [key, title, value, max] of [['label', '簡稱', label, 20], ['name', '完整名稱', name, 80]]) {
    const field = document.createElement('label');
    field.textContent = title;
    const input = document.createElement('input');
    input.dataset.field = key;
    input.value = value;
    input.required = true;
    input.maxLength = max;
    field.append(input);
    row.append(field);
  }
  const dayLabel = document.createElement('label');
  dayLabel.textContent = '每週星期';
  const days = document.createElement('select');
  days.dataset.field = 'weekday';
  weekdays.forEach((day, index) => days.add(new Option(`星期${day}`, String(index + 1))));
  days.value = String(weekday);
  dayLabel.append(days);
  row.append(dayLabel);
  const remove = document.createElement('button');
  remove.type = 'button';
  remove.className = 'secondary';
  remove.textContent = '移除';
  remove.setAttribute('aria-label', '移除此種聚會');
  remove.addEventListener('click', () => {
    if ($('services').children.length > 1) row.remove();
    else showError({ message: '至少保留一種聚會' });
  });
  row.append(remove);
  $('services').append(row);
}

function summaryRow(label, value, list = $('summary')) {
  const term = document.createElement('dt');
  const description = document.createElement('dd');
  term.textContent = label;
  description.textContent = value;
  list.append(term, description);
}

// Lowercase as they type, so the preview matches what the plan will accept.
function updateSitePreview() {
  const field = $('site-name');
  const value = field.value.toLowerCase();
  if (field.value !== value) field.value = value;
  const preview = $('site-preview').querySelector('strong');
  preview.textContent = `${value || '你填的名稱'}.pages.dev`;
}

function renderSteps(list, steps) {
  list.replaceChildren();
  for (const step of steps) {
    const item = document.createElement('li');
    item.dataset.state = step.status;
    const label = document.createElement('span');
    label.textContent = step.label;
    const status = document.createElement('span');
    status.className = 'step-state';
    status.textContent = stateLabels[step.status] ?? '需要核對';
    if (step.status === 'running') {
      if (!runningSince.has(`update:${step.id}`)) runningSince.set(`update:${step.id}`, Date.now());
      status.textContent += ` · ${elapsed(runningSince.get(`update:${step.id}`))}${slowSteps[step.id] ? `（${slowSteps[step.id]}）` : ''}`;
    } else runningSince.delete(`update:${step.id}`);
    item.append(label, status);
    list.append(item);
  }
}

// The five icon files, drawn from the church's image on a solid background.
// "any" icons keep a small margin; maskable ones keep the logo inside the
// centre circle that Android may crop to.
const ICONS = [['favicon.png', 32, 0.96], ['icons/Icon-192.png', 192, 0.84], ['icons/Icon-512.png', 512, 0.84],
  ['icons/Icon-maskable-192.png', 192, 0.62], ['icons/Icon-maskable-512.png', 512, 0.62]];
// The same picker serves a first install and an update; each has its own elements.
const LOGO_PICKERS = {
  install: { prefix: 'install-logo', reset: 'install-logo-reset' },
  update: { prefix: 'logo' },
};
const logoBitmaps = { install: undefined, update: undefined };
const logoElement = (kind, part) => $(`${LOGO_PICKERS[kind].prefix}-${part}`);
// A first-install logo changed after 檢查並預覽安裝: the shown plan no longer matches.
let installLogoChanged = false;

function drawIcon(canvas, bitmap, size, scale, background) {
  canvas.width = size;
  canvas.height = size;
  const context = canvas.getContext('2d');
  context.fillStyle = background;
  context.fillRect(0, 0, size, size);
  const fit = Math.min((size * scale) / bitmap.width, (size * scale) / bitmap.height);
  const width = bitmap.width * fit;
  const height = bitmap.height * fit;
  context.imageSmoothingQuality = 'high';
  context.drawImage(bitmap, (size - width) / 2, (size - height) / 2, width, height);
}

async function base64Png(canvas) {
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/png'));
  const bytes = new Uint8Array(await blob.arrayBuffer());
  let binary = '';
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(binary);
}

function previewLogo(kind) {
  const bitmap = logoBitmaps[kind];
  if (!bitmap) return;
  const background = logoElement(kind, 'background').value;
  drawIcon(logoElement(kind, 'preview-icon'), bitmap, 192, 0.84, background);
  drawIcon(logoElement(kind, 'preview-mask'), bitmap, 192, 0.62, background);
  logoElement(kind, 'preview').hidden = false;
  if (LOGO_PICKERS[kind].reset) $(LOGO_PICKERS[kind].reset).hidden = false;
}

// The five icon files drawn from the picked image, or nothing without a logo.
async function logoIcons(kind) {
  const bitmap = logoBitmaps[kind];
  if (!bitmap) return undefined;
  const background = logoElement(kind, 'background').value;
  const icons = {};
  for (const [name, size, scale] of ICONS) {
    const canvas = document.createElement('canvas');
    drawIcon(canvas, bitmap, size, scale, background);
    icons[name] = await base64Png(canvas);
  }
  return icons;
}

function clearLogo(kind) {
  logoBitmaps[kind] = undefined;
  logoElement(kind, 'file').value = '';
  logoElement(kind, 'preview').hidden = true;
  if (LOGO_PICKERS[kind].reset) $(LOGO_PICKERS[kind].reset).hidden = true;
}

// A picture that cannot be read clears the picker, so the last one is never sent instead.
async function pickLogo(kind) {
  const file = logoElement(kind, 'file').files[0];
  if (!file) return false;
  try {
    if (file.size > 20 * 1024 * 1024) throw new Error('圖片太大了，請換一張 20 MB 以下的圖片');
    try { logoBitmaps[kind] = await createImageBitmap(file); }
    catch { throw new Error('讀不到這張圖片，請換一張 PNG 或 JPG'); }
  } catch (error) {
    clearLogo(kind);
    throw error;
  }
  previewLogo(kind);
  return true;
}

async function uploadLogo() {
  previewLogo('update');
  const icons = await logoIcons('update');
  if (icons) await request('/api/update/icons', { icons });
}

// Update mode: pick a site this wizard installed, confirm, rebuild it.
function renderUpdate(state) {
  const update = state.update;
  const installing = Boolean(state.plan) && state.status !== 'complete';
  $('update-section').hidden = installing;
  // Collapsed for first installs; once someone is updating, keep it open.
  if ((state.installs || update) && !$('update-panel').open) $('update-panel').open = true;
  $('find-installs').disabled = state.busy || !state.identity.googleEmail || !state.identity.accounts.length || update?.status === 'running';
  $('release-line').hidden = !state.release;
  if (state.release) {
    $('release-line').textContent = `這次會更新到 ${state.release.version}${state.release.notes?.length ? `：${state.release.notes.join('；')}` : ''}`;
  }
  const nextInstallsKey = JSON.stringify([state.installs, update?.pagesProject, update?.cloudflareAccountId]);
  if (installsKey !== nextInstallsKey) {
    installsKey = nextInstallsKey;
    $('installs').replaceChildren();
    if (state.installs && !state.installs.length) {
      const empty = document.createElement('p');
      empty.className = 'hint';
      empty.textContent = '這組 Google／Cloudflare 帳號底下找不到安裝精靈裝過的網站。請確認連接的是當初安裝用的帳號（可以對照交接卡）。';
      $('installs').append(empty);
    }
    for (const install of state.installs ?? []) {
      const option = document.createElement('label');
      option.className = `install${install.readable ? '' : ' disabled'}`;
      const radio = document.createElement('input');
      radio.type = 'radio';
      radio.name = 'install';
      radio.disabled = !install.readable;
      radio.checked = update?.pagesProject === install.pagesProject && update?.cloudflareAccountId === install.accountId;
      radio.addEventListener('change', () => perform(() => request('/api/update/plan', { pagesProject: install.pagesProject, accountId: install.accountId })));
      const text = document.createElement('span');
      const name = document.createElement('span');
      name.className = 'name';
      name.textContent = install.appName ?? install.pagesProject;
      const meta = document.createElement('span');
      meta.className = 'meta';
      meta.textContent = [install.website, install.currentRelease ? `目前版本 ${install.currentRelease}` : null,
        install.readable ? null : '舊版精靈裝的，讀不到教會設定，無法自動更新'].filter(Boolean).join(' · ');
      text.append(name, document.createElement('br'), meta);
      option.append(radio, text);
      $('installs').append(option);
    }
  }
  $('update-confirm').hidden = !update;
  if (update) {
    const key = JSON.stringify([update.pagesProject, update.cloudflareAccountId]);
    if (updateKey !== key) {
      updateKey = key;
      $('update-summary').replaceChildren();
      summaryRow('教會名稱', update.appName, $('update-summary'));
      summaryRow('網站', update.website, $('update-summary'));
      summaryRow('版本', `${update.currentRelease ?? '較早的版本'} → ${update.release ?? '最新版'}`, $('update-summary'));
      summaryRow('會變更', '網站程式、資料存取規則', $('update-summary'));
      summaryRow('不會變更', '同工帳號、服事表、所有資料', $('update-summary'));
      $('confirm-update-label').textContent = `確認要更新 ${update.website}。`;
      $('confirm-update').checked = false;
    }
    renderSteps($('update-steps'), update.steps);
    $('update-steps').hidden = update.status === 'ready';
    $('apply-update').hidden = update.status === 'complete';
    $('apply-update').textContent = update.status === 'paused' ? '重新開始更新' : '開始更新';
    $('apply-update').disabled = state.busy || !$('confirm-update').checked;
    $('cancel-update').hidden = !(state.busy && update.status === 'running');
    $('icon-source').textContent = { new: '這次更新會換成下面的新 Logo。', live: '目前沿用網站現在的圖示。要換的話，選一張教會的 Logo 圖片。', neutral: '目前是預設圖示。要換成教會 Logo 的話，選一張圖片。' }[update.iconSource] ?? '';
    $('logo-reset').hidden = update.iconSource === 'neutral';
    if (update.iconSource !== 'new') $('logo-preview').hidden = true;
    for (const id of ['logo-file', 'logo-background', 'logo-reset', 'custom-domain']) $(id).disabled = state.busy || update.status === 'running';
    if (update.customDomain && !$('custom-domain').value) $('custom-domain').value = update.customDomain;
  }
  $('update-done').hidden = update?.status !== 'complete';
  if (update?.status === 'complete') {
    $('update-done-message').textContent = [update.unchanged
      ? `${update.website} 的網站程式已經是最新版本，不需要重新發布。`
      : '已更新完成。同工下次打開 App（或重新整理）就會換到新版；手機上已加到桌面的 App，關掉重開一次即可。',
    update.domain?.status === 'active' ? `自訂網址 https://${update.customDomain}/ 已經生效，可以改用這個網址分享給同工。` : ''].filter(Boolean).join(' ');
    $('update-website').href = update.website;
  }
  const dns = update?.status === 'complete' && update.domain && update.domain.status !== 'active' ? update.domain.cname : null;
  $('domain-instructions').hidden = !dns;
  if (dns) {
    $('dns-zone').textContent = dns.fullName.split('.').slice(1).join('.');
    $('dns-name').textContent = dns.name;
    $('dns-full').textContent = dns.fullName;
    $('dns-target').textContent = dns.target;
  }
}

function render(state) {
  current = state;
  $('demo-banner').hidden = !state.demo;
  if (state.busy) busySince ??= Date.now(); else busySince = undefined;
  const message = state.message || '先連接 Google 與 Cloudflare 帳號';
  $('status').textContent = busySince ? `${message}（已經過 ${elapsed(busySince)}）` : message;
  $('google-identity').textContent = state.identity.googleEmail ? `已連接：${state.identity.googleEmail}` : '尚未連接';
  $('google-switch').hidden = !state.identity.googleEmail || Boolean(state.plan);
  $('cloudflare-identity').textContent = state.identity.cloudflareEmail ? `已連接：${state.identity.cloudflareEmail}` : '尚未連接';
  $('connect-google').disabled = state.busy;
  $('connect-cloudflare').disabled = state.busy;
  $('resume').disabled = state.busy;
  $('settings-fields').disabled = state.busy || ['running', 'paused', 'complete'].includes(state.status) || Boolean(state.update);
  $('plan').disabled = state.busy || !state.identity.googleEmail || !state.identity.accounts.length;
  $('device').hidden = !state.device;
  if (state.device) {
    $('device-code').textContent = state.device.code;
    $('device-link').href = state.device.url;
    const left = state.device.expiresInMs === undefined ? undefined : Math.ceil(state.device.expiresInMs / 1000);
    $('device-expiry').hidden = left === undefined;
    if (left !== undefined) {
      $('device-expiry').textContent = left > 0
        ? `請在 ${Math.floor(left / 60)} 分 ${String(left % 60).padStart(2, '0')} 秒內按 Authorize。逾時請重新按「連接 Cloudflare」取得新代碼。`
        : '這組代碼已過期。請按「連接 Cloudflare」取得新代碼，不要再授權舊代碼。';
    }
  }
  if (!regionsReady) {
    for (const [id, name] of state.regions) $('region').add(new Option(`${name} · ${id}`, id));
    regionsReady = true;
  }
  const nextAccountsKey = JSON.stringify(state.identity.accounts);
  if (accountsKey !== nextAccountsKey) {
    const selected = $('cloudflare-account').value;
    $('cloudflare-account').replaceChildren(new Option('請選擇帳號', ''));
    for (const account of state.identity.accounts) $('cloudflare-account').add(new Option(account.name || account.id, account.id));
    if (state.identity.accounts.some((account) => account.id === selected)) $('cloudflare-account').value = selected;
    else if (state.identity.accounts.length === 1) $('cloudflare-account').value = state.identity.accounts[0].id;
    accountsKey = nextAccountsKey;
  }
  $('confirmation').hidden = !state.plan;
  $('progress-section').hidden = !state.plan;
  $('complete').hidden = state.status !== 'complete';
  if (state.plan) {
    const plan = state.plan;
    if (displayedPlan !== plan.digest) {
      $('summary').replaceChildren();
      summaryRow('教會名稱', plan.churchConfig.appName);
      summaryRow('Google 帳號', plan.googleEmail);
      summaryRow('新專案名稱', plan.projectId);
      summaryRow('Cloudflare 帳號', state.identity.accounts.find((account) => account.id === plan.cloudflareAccountId)?.name || plan.cloudflareAccountId);
      summaryRow('網站', `${plan.pagesProject}.pages.dev（名稱被其他人用過的話，Cloudflare 會在後面加幾個字，實際網址以完成頁為準）`);
      summaryRow('資料儲存地區', `${state.regions.find(([id]) => id === plan.region)?.[1] || ''} · ${plan.region}`);
      summaryRow('教會 Logo', plan.icons ? '自訂 Logo' : '預設圖示');
      summaryRow('教會時區', plan.churchConfig.timeZone);
      summaryRow('每週聚會', plan.churchConfig.services.map((service) => `${service.name}（週${weekdays[service.weekday - 1]}）`).join('、'));
      summaryRow('指定管理員', `${plan.admin.name} · ${plan.admin.email}`);
      $('email-confirm-label').textContent = `確認 ${plan.admin.email} 是指定管理員，同意建立此帳號及寄送設定密碼信。`;
      $('confirm-region').checked = false;
      $('confirm-email').checked = false;
      displayedPlan = plan.digest;
    }
    $('run-id').textContent = plan.runId;
    $('resume-id').value = plan.runId;
    $('steps').replaceChildren();
    for (const step of state.steps) {
      const item = document.createElement('li');
      item.dataset.state = step.status;
      const label = document.createElement('span');
      label.textContent = step.label;
      const status = document.createElement('span');
      status.className = 'step-state';
      status.textContent = step.status === 'waiting' && laterCodes.has(state.error?.code)
        ? '稍後接續' : stateLabels[step.status] ?? '需要核對';
      if (step.status === 'running') {
        if (!runningSince.has(step.id)) runningSince.set(step.id, Date.now());
        status.textContent += ` · ${elapsed(runningSince.get(step.id))}${slowSteps[step.id] ? `（${slowSteps[step.id]}）` : ''}`;
      } else runningSince.delete(step.id);
      item.append(label, status);
      $('steps').append(item);
    }
    $('apply').textContent = state.status === 'paused'
      ? laterCodes.has(state.error?.code) ? '稍後接續安裝' : '核對後接續安裝'
      : '確認並開始安裝';
    $('apply').hidden = state.status === 'complete';
    $('cancel').hidden = !state.busy;
  }
  updateApply();
  renderUpdate(state);
  if (state.website) $('website').href = state.website;
  if (state.status === 'complete' && state.plan) {
    renderCleanup(state.plan);
    renderHandoff(state);
  }
  showError(state.error);
}

// Only the IDs this run created. Deleting stays a manual, official-console action.
function renderCleanup(plan) {
  const project = encodeURIComponent(plan.projectId);
  const account = encodeURIComponent(plan.cloudflareAccountId);
  $('mail-sender').textContent = `noreply@${plan.projectId}.firebaseapp.com`;
  $('cleanup-google-id').textContent = plan.projectId;
  $('cleanup-google').href = `https://console.cloud.google.com/iam-admin/settings?project=${project}`;
  $('cleanup-cloudflare-id').textContent = plan.pagesProject;
  $('cleanup-cloudflare').href = `https://dash.cloudflare.com/${account}/pages/view/${encodeURIComponent(plan.pagesProject)}`;
}

// What the church needs later to find, update or hand over this install.
// Only identifiers the operator already sees; no credentials.
function handoffRows(state) {
  const plan = state.plan;
  const account = state.identity.accounts.find((item) => item.id === plan.cloudflareAccountId);
  return [
    ['網站網址', state.website ?? `https://${plan.pagesProject}.pages.dev/`],
    ['教會名稱', plan.churchConfig.appName],
    ['首位管理員', `${plan.admin.name} · ${plan.admin.email}`],
    ['Google 帳號', plan.googleEmail],
    ['Google 專案 ID', plan.projectId],
    ['Cloudflare 帳號', [account?.name, state.identity.cloudflareEmail].filter(Boolean).join(' · ') || plan.cloudflareAccountId],
    ['Cloudflare 網站名稱', plan.pagesProject],
    ['安裝識別碼', plan.runId],
    ['安裝日期', new Date().toLocaleDateString('zh-TW')],
  ];
}

function shareMessage(state) {
  const url = new URL(state.website ?? `https://${state.plan.pagesProject}.pages.dev/`);
  url.searchParams.set('openExternalBrowser', '1');
  return [
    `「${state.plan.churchConfig.appName}」上線了！`,
    `登入網址：${url.href}`,
    '帳號是管理員幫你建立的 Email。忘記密碼的話，在登入頁按「忘記密碼？」。',
    '第一次打開後，請加到手機主畫面，之後就像 App 一樣點開：',
    '・iPhone：用 Safari 開啟，按下方工具列的「分享」→「加入主畫面」（下方只有網址列的話，先按網址列右邊的「⋯」→「分享」）',
    '・Android：用 Chrome 開啟，按右上角「⋮」→「安裝應用程式」或「加到主畫面」',
  ].join('\n');
}

let renderedHandoff;
function renderHandoff(state) {
  const key = `${state.plan.digest}:${state.website}`;
  if (renderedHandoff === key) return;
  $('handoff').replaceChildren();
  for (const [label, value] of handoffRows(state)) summaryRow(label, value, $('handoff'));
  $('share-message').value = shareMessage(state);
  renderedHandoff = key;
}

async function copyText(text, button) {
  await navigator.clipboard.writeText(text);
  const original = button.textContent;
  button.textContent = '已複製';
  setTimeout(() => { button.textContent = original; }, 2_000);
}

function updateApply() {
  $('logo-stale').hidden = !installLogoChanged || !current?.plan || current.status !== 'ready';
  $('apply').disabled = !current?.plan || current.busy || !$('confirm-region').checked || !$('confirm-email').checked ||
    !current.identity.googleEmail || !current.identity.accounts.length || !$('logo-stale').hidden;
}

function markInstallLogoChanged() {
  if (current?.plan) installLogoChanged = true;
  updateApply();
}

async function refresh() {
  if (fetching) return;
  fetching = true;
  try { render(await request('/api/state')); }
  catch (error) {
    if (error.status === 401) {
      clearInterval(timer);
      $('fatal').hidden = false;
      $('fatal').textContent = error.message;
      document.querySelectorAll('button').forEach((button) => { button.disabled = true; });
    } else showError({ message: '與 Cloud Shell 的連線暫時中斷。請保持分頁開啟；恢復連線後會重新讀取進度，不會另建專案。' });
  } finally { fetching = false; }
}

async function loadRuns() {
  const runs = await request('/api/runs');
  $('resume-existing').replaceChildren(new Option('請選擇紀錄，或在下方貼上識別碼', ''));
  for (const run of runs) $('resume-existing').add(new Option(`${run.appName} · ${run.projectId}`, run.runId));
}

for (const provider of ['google', 'cloudflare']) {
  $(`connect-${provider}`).addEventListener('click', () => perform(() => {
    $(`connect-${provider}`).disabled = true;
    return request(`/api/connect/${provider}`, {});
  }));
}
$('add-service').addEventListener('click', () => addService());
$('site-name').addEventListener('input', updateSitePreview);
$('copy-share').addEventListener('click', () => perform(() => copyText($('share-message').value, $('copy-share'))));
$('copy-handoff').addEventListener('click', () => perform(() => copyText(
  handoffRows(current).map(([label, value]) => `${label}：${value}`).join('\n'), $('copy-handoff'))));
$('confirm-region').addEventListener('change', updateApply);
$('confirm-email').addEventListener('change', updateApply);
$('settings-form').addEventListener('submit', (event) => {
  event.preventDefault();
  void perform(async () => {
    const values = Object.fromEntries(new FormData(event.currentTarget));
    values.services = [...$('services').children].map((row) => ({
      label: row.querySelector('[data-field="label"]').value,
      name: row.querySelector('[data-field="name"]').value,
      weekday: Number(row.querySelector('[data-field="weekday"]').value),
    }));
    const icons = await logoIcons('install');
    if (icons) values.icons = icons;
    await request('/api/plan', values);
    installLogoChanged = false;
    await loadRuns();
    $('confirmation').scrollIntoView({ behavior: 'smooth', block: 'start' });
  });
});
$('apply').addEventListener('click', () => perform(() => {
  // Block a second click before the next state refresh arrives.
  $('apply').disabled = true;
  return request('/api/apply', {
    digest: current.plan.digest, confirmProject: current.plan.projectId, confirmAdmin: current.plan.admin.email,
    acknowledgeRegion: $('confirm-region').checked, acknowledgeEmail: $('confirm-email').checked,
  });
}));
$('cancel').addEventListener('click', () => perform(() => request('/api/cancel', {})));
$('find-installs').addEventListener('click', () => perform(() => request('/api/update/find', {})));
$('confirm-update').addEventListener('change', () => { $('apply-update').disabled = current?.busy || !$('confirm-update').checked; });
$('apply-update').addEventListener('click', () => perform(() => {
  $('apply-update').disabled = true;
  return request('/api/update/apply', { confirm: current.update.pagesProject, customDomain: $('custom-domain').value.trim() || undefined });
}));
$('cancel-update').addEventListener('click', () => perform(() => request('/api/cancel', {})));
$('logo-file').addEventListener('change', () => perform(async () => { if (await pickLogo('update')) await uploadLogo(); }));
$('logo-background').addEventListener('change', () => perform(uploadLogo));
$('logo-reset').addEventListener('click', () => perform(async () => {
  clearLogo('update');
  await request('/api/update/icons', { reset: true });
}));
// A first install's logo is only drawn here; it is sent with 檢查並預覽安裝.
$('install-logo-file').addEventListener('change', () => perform(async () => {
  try { await pickLogo('install'); } finally { markInstallLogoChanged(); }
}));
$('install-logo-background').addEventListener('change', () => { previewLogo('install'); markInstallLogoChanged(); });
$('install-logo-reset').addEventListener('click', () => { clearLogo('install'); markInstallLogoChanged(); });
$('resume-existing').addEventListener('change', () => { $('resume-id').value = $('resume-existing').value; });
$('resume').addEventListener('click', () => perform(() => request('/api/resume', { runId: $('resume-id').value.trim() })));
$('copy-id').addEventListener('click', () => perform(async () => {
  await navigator.clipboard.writeText(current.plan.runId);
  $('copy-id').textContent = '已複製';
}));

// The link token is kept in this tab's sessionStorage until the server has
// seen the session cookie, so a first open that loses the cookie on Cloud
// Shell's sign-in redirect recovers by itself instead of needing the link again.
const TOKEN_KEY = 'installer-link';
const RETRY_KEY = 'installer-link-retries';
const stored = {
  get: (key) => { try { return sessionStorage.getItem(key) ?? ''; } catch { return ''; } },
  set: (key, value) => { try { sessionStorage.setItem(key, value); } catch { /* Private mode: the link still works once. */ } },
  clear: () => { try { sessionStorage.removeItem(TOKEN_KEY); sessionStorage.removeItem(RETRY_KEY); } catch { /* Nothing stored. */ } },
};

async function openSession(token) {
  try { await request('/api/session', { token }); }
  catch (error) {
    if (error.status !== 401) throw error;
    // An already authenticated tab can reopen an expired private link.
    await request('/api/session').catch(() => { throw error; });
  }
  // A Cloud Shell sign-in redirect can keep Strict cookies off the first
  // document's fetches. Navigate once, without the token, before reading
  // state; this also keeps the token out of browser history.
  location.replace(location.pathname);
}

async function start() {
  addService({ label: '主日', name: '主日崇拜', weekday: 7 });
  updateSitePreview();
  const token = new URLSearchParams(location.search).get('k') || location.hash.slice(1);
  history.replaceState(null, '', location.pathname);
  try {
    if (token) {
      stored.set(TOKEN_KEY, token);
      stored.set(RETRY_KEY, '0');
      await openSession(token);
      return;
    }
    let session;
    try { session = await request('/api/session'); }
    catch (error) {
      const retries = Number(stored.get(RETRY_KEY)) || 0;
      if (error.status !== 401 || !stored.get(TOKEN_KEY) || retries >= 2) throw error;
      stored.set(RETRY_KEY, String(retries + 1));
      await openSession(stored.get(TOKEN_KEY));
      return;
    }
    stored.clear();
    csrf = session.csrf;
    render(await request('/api/state'));
    await loadRuns();
    timer = setInterval(refresh, 1_500);
  } catch (error) {
    $('fatal').hidden = false;
    $('status').hidden = true;
    // The first open of a Web Preview goes through Google's sign-in check,
    // which returns to "/" and drops the link's code. The second open works.
    $('fatal').textContent = error.status === 401 && !token && !stored.get(TOKEN_KEY)
      ? '還差一步：Google 剛才先確認了你的帳號，所以這次沒有帶到私人連結的代碼。請回到 Cloud Shell 分頁，再點一次終端機裡同一個連結，第二次就會直接開啟。這個分頁可以關掉。'
      : error.status === 401 && !token
        ? '瀏覽器沒有保留精靈的登入資訊。請用同一個瀏覽器、不要用無痕視窗，回到 Cloud Shell 分頁再點一次連結。已建立的安裝紀錄不會刪除。'
        : error.message || '無法開啟私人精靈，請重新執行啟動命令';
    document.querySelectorAll('button').forEach((button) => { button.disabled = true; });
  }
}
void start();
