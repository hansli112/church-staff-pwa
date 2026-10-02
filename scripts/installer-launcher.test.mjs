import assert from 'node:assert/strict';
import { chmod, cp, lstat, mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { runCommand } from './installer/process.mjs';
import { git } from './test-git.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const cloudShell = process.platform === 'linux' && os.arch() === 'x64';

// An origin whose history is: before-floor, floor, old (an earlier release),
// current (the clone's checkout) and latest (not yet in the clone), a clone of
// it, and a launch() that runs the launcher there and stops at its disk check.
async function launcherRepository(t, { shallow = false } = {}) {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'installer-launcher-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const origin = path.join(dir, 'origin');
  await mkdir(path.join(origin, 'scripts/installer'), { recursive: true });
  await cp(path.join(ROOT, 'scripts/start-installation.sh'), path.join(origin, 'scripts/start-installation.sh'));
  await writeFile(path.join(origin, 'scripts/install-core.mjs'), '');
  await git(origin, 'init', '-q', '-b', 'main');
  const commit = async (name) => {
    await writeFile(path.join(origin, 'version.txt'), name);
    await git(origin, 'add', '-A');
    await git(origin, 'commit', '-q', '-m', name);
    return git(origin, 'rev-parse', 'HEAD');
  };
  const revisions = { beforeFloor: await commit('before-floor'), floor: await commit('floor'), old: await commit('old') };
  revisions.current = await commit('current');
  await writeFile(path.join(origin, 'scripts/installer/RESUMES_FROM'), `${revisions.floor}\n# note\n`);
  revisions.latest = await commit('latest');
  const clone = path.join(dir, 'clone');
  if (shallow) {
    // A one-commit clone of current: the floor and older versions are absent.
    await git(origin, 'branch', '-q', 'current', revisions.current);
    await git(dir, 'clone', '-q', '--depth', '1', '--branch', 'current', `file://${origin}`, clone);
    await git(clone, 'branch', '-q', '-m', 'main');
    await git(clone, 'config', 'remote.origin.fetch', '+refs/heads/main:refs/remotes/origin/main');
  } else {
    await git(dir, 'clone', '-q', origin, clone);
    await git(clone, 'reset', '-q', '--hard', revisions.current);
  }
  // Stop the launcher right after its update check: report a full disk.
  const bin = path.join(dir, 'bin');
  await mkdir(bin);
  await writeFile(path.join(bin, 'df'), '#!/bin/sh\nprintf "F 1K U A U%% M\\nfake 1 1 1 1%% /tmp\\n"\n');
  await chmod(path.join(bin, 'df'), 0o755);
  const record = async (runId, status, sourceRevision) => {
    await mkdir(path.join(clone, '.local/install', runId), { recursive: true });
    await writeFile(path.join(clone, '.local/install', runId, 'state.json'),
      JSON.stringify({ schemaVersion: 1, plan: { runId, sourceRevision }, status }, null, 2) + '\n');
  };
  const launch = async () => {
    const result = await runCommand('bash', ['scripts/start-installation.sh'], {
      cwd: clone, rejectOnExit: false, replaceEnv: true,
      env: { PATH: `${bin}:${process.env.PATH}`, HOME: dir, CLOUD_SHELL: 'true' },
    });
    return { output: result.stdout + result.stderr, head: await git(clone, 'rev-parse', 'HEAD') };
  };
  return { revisions, record, launch, clone };
}

test('the launcher updates a clone with no unfinished install', { skip: !cloudShell }, async (t) => {
  const { revisions, record, launch } = await launcherRepository(t);
  await record('11111111-1111-4111-8111-111111111111', 'complete', revisions.beforeFloor);
  const { output, head } = await launch();
  assert.match(output, /已更新到最新版本/);
  assert.equal(head, revisions.latest);
});

test('the launcher updates past an unfinished install the new version can continue', { skip: !cloudShell }, async (t) => {
  const { revisions, record, launch } = await launcherRepository(t);
  await record('11111111-1111-4111-8111-111111111111', 'paused', revisions.old);
  await record('22222222-2222-4222-8222-222222222222', 'failed', revisions.floor);
  const { output, head } = await launch();
  assert.match(output, /已更新到最新版本/);
  assert.equal(head, revisions.latest);
});

test('the launcher keeps the version of an unfinished install older than RESUMES_FROM', { skip: !cloudShell }, async (t) => {
  const { revisions, record, launch } = await launcherRepository(t);
  await record('11111111-1111-4111-8111-111111111111', 'paused', revisions.old);
  await record('22222222-2222-4222-8222-222222222222', 'failed', revisions.beforeFloor);
  const { output, head } = await launch();
  assert.match(output, /新版本無法接續，維持目前程式版本/);
  assert.equal(head, revisions.current);
});

test('the launcher keeps the version of an unfinished install it cannot read', { skip: !cloudShell }, async (t) => {
  const { record, revisions, launch } = await launcherRepository(t);
  await record('11111111-1111-4111-8111-111111111111', 'paused', 'development');
  const { output, head } = await launch();
  assert.match(output, /新版本無法接續/);
  assert.equal(head, revisions.current);
});

test('the launcher keeps the version of a shallow clone it cannot check', { skip: !cloudShell }, async (t) => {
  const { revisions, record, launch } = await launcherRepository(t, { shallow: true });
  await record('11111111-1111-4111-8111-111111111111', 'paused', revisions.old);
  const { output, head } = await launch();
  assert.match(output, /新版本無法接續/);
  assert.equal(head, revisions.current);
});

test('the launcher says nothing about updating a clone that is already the latest', { skip: !cloudShell }, async (t) => {
  const { revisions, record, launch, clone } = await launcherRepository(t);
  await record('11111111-1111-4111-8111-111111111111', 'paused', revisions.beforeFloor);
  await git(clone, 'reset', '-q', '--hard', revisions.latest);
  const { output, head } = await launch();
  assert.doesNotMatch(output, /更新|無法接續/);
  assert.equal(head, revisions.latest);
});

test('the launcher does not update while another wizard is running', { skip: !cloudShell }, async (t) => {
  const { revisions, launch } = await launcherRepository(t);
  // The launcher looks for live wizards where real sessions keep their marker.
  const base = `/tmp/church-core-installer-${process.getuid()}`;
  const created = !(await lstat(base).catch(() => null));
  if (created) await mkdir(base, { mode: 0o700 });
  const session = await mkdtemp(path.join(base, 'session-test-'));
  t.after(async () => { await rm(session, { recursive: true, force: true }); if (created) await rm(base, { recursive: true, force: true }); });
  await writeFile(path.join(session, '.installer-pid'), `${process.pid}\n`);
  const { output, head } = await launch();
  assert.match(output, /另一個安裝精靈還在執行/);
  assert.equal(head, revisions.current);
});
