import { spawn } from 'node:child_process';
import path from 'node:path';

const INHERITED_CREDENTIAL = /^(?:CLOUDFLARE_(?:API_TOKEN|API_KEY|EMAIL|ACCOUNT_ID)|CF_(?:API_TOKEN|API_KEY|EMAIL|ACCOUNT_ID)|GOOGLE_(?:OAUTH_ACCESS_TOKEN|APPLICATION_CREDENTIALS)|FIREBASE_TOKEN|GEMINI_API_KEY|WRANGLER_API_TOKEN)$/;

export function commandEnvironment(overrides = {}) {
  const environment = Object.fromEntries(
    Object.entries(process.env).filter(([key]) => !INHERITED_CREDENTIAL.test(key)),
  );
  for (const [key, value] of Object.entries(overrides)) {
    if (value === undefined || value === null) delete environment[key];
    else environment[key] = String(value);
  }
  return environment;
}

// Exact environment for build and Wrangler children. Never inherit credentials,
// proxy destinations, NODE_OPTIONS or Wrangler's alternate OAuth endpoints.
export function privateEnvironment(home, source = process.env) {
  const env = Object.fromEntries(['PATH', 'LANG', 'LC_ALL', 'TZ', 'SYSTEMROOT'].filter((key) => source[key]).map((key) => [key, source[key]]));
  return {
    ...env, HOME: home, XDG_CONFIG_HOME: path.join(home, 'config'),
    XDG_CACHE_HOME: path.join(home, 'cache'), XDG_DATA_HOME: path.join(home, 'data'),
    TMPDIR: path.join(home, 'tmp'), NO_COLOR: '1', CI: 'true',
    // 'log' is Wrangler's default. 'info' is a lower level and silences normal
    // output, including --version, whoami --json and the device-code prompt.
    WRANGLER_SEND_METRICS: 'false', WRANGLER_LOG: 'log',
    CLOUDFLARE_AUTH_USE_KEYRING: 'false',
  };
}

// Raw output stays server-side: errors carry stdout/stderr for the caller's own
// parser, but their messages never include it. `rejectOnExit: false` lets a
// caller inspect a non-zero exit code instead of receiving an error.
export function runCommand(executable, args, {
  cwd, env, signal, input, onStdout, onStderr, replaceEnv = false, rejectOnExit = true,
  timeoutMs = 120_000, maxOutputBytes = 8 * 1024 * 1024,
} = {}) {
  if (signal?.aborted) return Promise.reject(new Error('操作已取消'));
  return new Promise((resolve, reject) => {
    const child = spawn(executable, args, {
      cwd, env: replaceEnv ? { ...env } : commandEnvironment(env), shell: false,
      detached: process.platform !== 'win32',
      stdio: [input === undefined ? 'ignore' : 'pipe', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stderr = '';
    let bytes = 0;
    let failure;
    let killTimer;
    let settled = false;
    const kill = (signalName) => {
      try {
        if (process.platform !== 'win32' && child.pid) process.kill(-child.pid, signalName);
        else child.kill(signalName);
      } catch { /* The process may have exited while cancellation was requested. */ }
    };
    const stop = (message) => {
      if (failure || settled) return;
      failure = new Error(message);
      kill('SIGTERM');
      killTimer = setTimeout(() => kill('SIGKILL'), 5_000);
      killTimer.unref();
    };
    const abort = () => stop('操作已取消');
    const timer = setTimeout(() => stop('工具執行逾時'), timeoutMs);
    timer.unref();
    signal?.addEventListener('abort', abort, { once: true });
    const finish = (error, exitCode) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      clearTimeout(killTimer);
      signal?.removeEventListener('abort', abort);
      if (error) {
        Object.assign(error, { stdout, stderr, exitCode });
        reject(error);
      } else resolve({ stdout, stderr, exitCode });
    };
    const capture = (kind, callback) => (chunk) => {
      bytes += Buffer.byteLength(chunk);
      if (bytes > maxOutputBytes) return stop('工具輸出超過安全上限');
      const text = chunk.toString();
      if (kind === 'stdout') stdout += text;
      else stderr += text;
      try { callback?.(text); } catch { stop('無法解析工具回應'); }
    };
    child.stdout.on('data', capture('stdout', onStdout));
    child.stderr.on('data', capture('stderr', onStderr));
    child.on('error', () => finish(new Error('無法啟動必要工具')));
    child.on('close', (code) => finish(
      failure ?? (code === 0 || !rejectOnExit ? undefined : new Error('必要工具未成功完成')), code,
    ));
    if (child.stdin) {
      child.stdin.on('error', () => {});
      child.stdin.end(input);
    }
    if (signal?.aborted) abort();
  });
}

// Build and Wrangler children: exact environment, 1 MiB output cap, and the
// exit code returned for the caller to classify.
export function runIsolatedCommand(executable, args, options = {}) {
  return runCommand(executable, args, {
    maxOutputBytes: 1024 * 1024, ...options, replaceEnv: true, rejectOnExit: false,
  });
}
