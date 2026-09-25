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
const stateLabels = { pending: '尚未開始', running: '處理中', complete: '已完成', failed: '需要處理', paused: '已停止', waiting: '待本人操作' };
// Long steps say so up front; the elapsed time shows the wizard is still alive.
const slowSteps = { build: '可能需要十幾分鐘', publish: '可能需要幾分鐘' };
const runningSince = new Map();
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

function summaryRow(label, value) {
  const term = document.createElement('dt');
  const description = document.createElement('dd');
  term.textContent = label;
  description.textContent = value;
  $('summary').append(term, description);
}

function render(state) {
  current = state;
  $('demo-banner').hidden = !state.demo;
  if (state.busy) busySince ??= Date.now(); else busySince = undefined;
  const message = state.message || '先連接 Google 與 Cloudflare 帳號';
  $('status').textContent = busySince ? `${message}（已經過 ${elapsed(busySince)}）` : message;
  $('google-identity').textContent = state.identity.googleEmail || '尚未連接';
  $('cloudflare-identity').textContent = state.identity.cloudflareEmail || '尚未連接';
  $('connect-google').disabled = state.busy;
  $('connect-cloudflare').disabled = state.busy;
  $('resume').disabled = state.busy;
  $('settings-fields').disabled = state.busy || ['running', 'paused', 'complete'].includes(state.status);
  $('plan').disabled = state.busy || !state.identity.googleEmail || !state.identity.accounts.length;
  $('device').hidden = !state.device;
  if (state.device) {
    $('device-code').textContent = state.device.code;
    $('device-link').href = state.device.url;
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
      summaryRow('網站', `${plan.pagesProject}.pages.dev（實際網址以 Cloudflare 回覆為準）`);
      summaryRow('資料儲存地區', `${state.regions.find(([id]) => id === plan.region)?.[1] || ''} · ${plan.region}`);
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
      status.textContent = stateLabels[step.status] ?? '需要核對';
      if (step.status === 'running') {
        if (!runningSince.has(step.id)) runningSince.set(step.id, Date.now());
        status.textContent += ` · ${elapsed(runningSince.get(step.id))}${slowSteps[step.id] ? `（${slowSteps[step.id]}）` : ''}`;
      } else runningSince.delete(step.id);
      item.append(label, status);
      $('steps').append(item);
    }
    $('apply').textContent = state.status === 'paused' ? '核對後接續安裝' : '確認並開始安裝';
    $('apply').hidden = state.status === 'complete';
    $('cancel').hidden = !state.busy;
  }
  updateApply();
  if (state.website) $('website').href = state.website;
  showError(state.error);
}

function updateApply() {
  $('apply').disabled = !current?.plan || current.busy || !$('confirm-region').checked || !$('confirm-email').checked ||
    !current.identity.googleEmail || !current.identity.accounts.length;
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
    await request('/api/plan', values);
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
$('resume-existing').addEventListener('change', () => { $('resume-id').value = $('resume-existing').value; });
$('resume').addEventListener('click', () => perform(() => request('/api/resume', { runId: $('resume-id').value.trim() })));
$('copy-id').addEventListener('click', () => perform(async () => {
  await navigator.clipboard.writeText(current.plan.runId);
  $('copy-id').textContent = '已複製';
}));

async function start() {
  addService({ label: '主日', name: '主日崇拜', weekday: 7 });
  const token = location.hash.slice(1);
  history.replaceState(null, '', location.pathname);
  try {
    const session = await request('/api/session', token ? { token } : undefined);
    csrf = session.csrf;
    await refresh();
    await loadRuns();
    timer = setInterval(refresh, 1_500);
  } catch (error) {
    $('fatal').hidden = false;
    $('fatal').textContent = error.message || '無法開啟私人精靈，請重新執行啟動命令';
    document.querySelectorAll('button').forEach((button) => { button.disabled = true; });
  }
}
void start();
