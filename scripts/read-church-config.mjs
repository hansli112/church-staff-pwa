#!/usr/bin/env node
// Local operator scripts deliberately require a deployment config rather than
// silently running against the example configuration.
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateChurchConfig } from '../worker/church_config.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export function readChurchConfig(file = process.env.CHURCH_CONFIG_FILE || path.join(ROOT, '.local/church.json')) {
  try {
    return validateChurchConfig(JSON.parse(readFileSync(file, 'utf8')));
  } catch (error) {
    throw new Error(`Church config: ${error.message}. Set CHURCH_CONFIG_FILE or create .local/church.json from config/church.example.json.`);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { console.log(JSON.stringify(readChurchConfig(process.argv[2]))); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
