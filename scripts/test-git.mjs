import { runCommand } from './installer/process.mjs';

// git for tests that build throwaway repositories: a fixed identity, trimmed output.
export const git = (cwd, ...args) => runCommand('git', ['-c', 'user.name=t', '-c', 'user.email=t@example.invalid', ...args], { cwd })
  .then(({ stdout }) => stdout.trim());
