#!/usr/bin/env node
/**
 * Local dev on an iPad Simulator (defaults to latest 13-inch Pro):
 *   npm run dev:ipad
 *
 * Starts donna-server-go + Metro, syncs voice env, boots simulator, builds app.
 * Optional in .env: DONNA_IOS_SIMULATOR=<name or UDID> to pick a device
 * (e.g. "iPad Air 13-inch (M3)" or a simctl UDID).
 */
import { spawn, execSync } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..');
const appRoot = path.join(repoRoot, 'donna-app');
const serverRoot = path.join(repoRoot, 'donna-server-go');
const serverBin = path.join(serverRoot, 'bin', 'donna-server');
const envPath = path.join(repoRoot, '.env');
const port = Number(process.env.DONNA_PORT) || 8787;

const children = [];
let shuttingDown = false;

function log(msg) {
  console.log(`[dev:ipad] ${msg}`);
}

function fail(msg) {
  console.error(`[dev:ipad] ${msg}`);
  process.exit(1);
}

function parseEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return {};
  const vars = {};
  for (const line of fs.readFileSync(filePath, 'utf8').split('\n')) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const eq = trimmed.indexOf('=');
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    let value = trimmed.slice(eq + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    vars[key] = value;
  }
  return vars;
}

function requireMacOS() {
  if (process.platform !== 'darwin') {
    fail('iPad Simulator requires macOS + Xcode.');
  }
}

function requireCommand(cmd, hint) {
  try {
    execSync(`command -v ${cmd}`, { stdio: 'ignore' });
  } catch {
    fail(hint ?? `Missing required command: ${cmd}`);
  }
}

function validateEnv(env) {
  if (!fs.existsSync(envPath)) {
    fail(
      'Missing .env — run: cp .env.example .env and add OPENROUTER_API_KEY + a TTS key.',
    );
  }

  const missing = [];
  if (!env.OPENROUTER_API_KEY?.trim()) missing.push('OPENROUTER_API_KEY');
  if (!env.DONNA_LLM_MODEL?.trim()) missing.push('DONNA_LLM_MODEL');

  const hasTts =
    env.OPENAI_API_KEY?.trim() ||
    env.CARTESIA_API_KEY?.trim() ||
    env.ELEVENLABS_API_KEY?.trim();
  if (!hasTts) {
    missing.push('OPENAI_API_KEY or CARTESIA_API_KEY or ELEVENLABS_API_KEY');
  }

  if (missing.length) {
    fail(`Set these in .env: ${missing.join(', ')}`);
  }

  if (env.DONNA_VOICE_TARGET === 'production') {
    fail(
      'DONNA_VOICE_TARGET=production — set DONNA_VOICE_TARGET=local in .env for local dev.',
    );
  }
}

function ensureDependencies() {
  if (!fs.existsSync(path.join(repoRoot, 'node_modules'))) {
    log('Installing root npm dependencies…');
    execSync('npm install', { cwd: repoRoot, stdio: 'inherit' });
  }
  if (!fs.existsSync(path.join(appRoot, 'node_modules'))) {
    log('Installing donna-app npm dependencies…');
    execSync('npm install', { cwd: appRoot, stdio: 'inherit' });
  }
  const podsDir = path.join(appRoot, 'ios', 'Pods');
  if (!fs.existsSync(podsDir)) {
    log('Running pod install…');
    execSync('pod install', {
      cwd: path.join(appRoot, 'ios'),
      stdio: 'inherit',
    });
  }
}

function normalizeDeviceName(name) {
  return name
    .replace(/[\u2018\u2019\u0060\u00B4]/g, "'")
    .trim()
    .toLowerCase();
}

function chipRank(name) {
  const match = name.match(/\((M\d+)\)/i);
  if (!match) return 0;
  return Number(match[1].slice(1)) || 0;
}

function listIpadSimulators() {
  let raw;
  try {
    raw = execSync('xcrun simctl list devices available -j', {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      maxBuffer: 20 * 1024 * 1024,
    });
  } catch {
    fail('Could not list simulators — is Xcode installed?');
  }

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    fail('Could not parse simctl device list JSON.');
  }

  const devices = [];
  for (const [runtime, runtimeDevices] of Object.entries(
    parsed.devices ?? {},
  )) {
    if (!/iOS/i.test(runtime)) continue;
    for (const device of runtimeDevices ?? []) {
      if (!device?.isAvailable) continue;
      if (!/^iPad/i.test(device.name ?? '')) continue;
      devices.push({
        name: device.name,
        udid: device.udid,
        state: device.state,
        runtime,
      });
    }
  }
  return devices;
}

function scoreIpad13(device) {
  const name = device.name;
  if (!/13[- ]?inch/i.test(name)) return -1;

  let score = 100;
  if (/Pro/i.test(name)) score += 30;
  else if (/Air/i.test(name)) score += 10;
  score += chipRank(name) * 5;
  if (/Booted/i.test(device.state)) score += 2;
  return score;
}

function pickSimulator(devices, fileEnv) {
  const preferred = (
    process.env.DONNA_IOS_SIMULATOR ?? fileEnv.DONNA_IOS_SIMULATOR
  )?.trim();

  if (preferred) {
    const normalizedPreferred = normalizeDeviceName(preferred);
    const hit =
      devices.find((d) => d.udid === preferred) ??
      devices.find((d) => d.name === preferred) ??
      devices.find(
        (d) => normalizeDeviceName(d.name) === normalizedPreferred,
      ) ??
      devices.find((d) =>
        normalizeDeviceName(d.name).includes(normalizedPreferred),
      );
    if (!hit) {
      fail(
        `No iPad simulator matches DONNA_IOS_SIMULATOR="${preferred}". Available: ${devices.map((d) => `${d.name} (${d.udid})`).join(', ') || '(none)'}`,
      );
    }
    return hit;
  }

  const ranked = devices
    .map((d) => ({ device: d, score: scoreIpad13(d) }))
    .filter((x) => x.score >= 0)
    .sort((a, b) => b.score - a.score);

  if (ranked.length === 0) {
    fail(
      'No 13-inch iPad simulator found. Install one in Xcode → Settings → Platforms, or set DONNA_IOS_SIMULATOR.',
    );
  }

  const best = ranked[0];
  if (ranked.length > 1 && ranked[1].score === best.score) {
    log(
      `Multiple matching simulators — using ${best.device.name}. Set DONNA_IOS_SIMULATOR to override.`,
    );
  }
  return best.device;
}

function bootSimulator(device) {
  if (/Booted/i.test(device.state)) {
    log(`Simulator already booted: ${device.name}`);
    return;
  }
  log(`Booting ${device.name}…`);
  try {
    execSync(`xcrun simctl boot ${device.udid}`, { stdio: 'inherit' });
  } catch {
    // Already booted races are fine.
  }
  try {
    execSync('open -a Simulator', { stdio: 'ignore' });
  } catch {
    // Simulator.app may already be open.
  }
}

function syncAppEnv() {
  execSync('node scripts/sync-env.mjs', { cwd: appRoot, stdio: 'inherit' });
}

function buildServer(env) {
  fs.mkdirSync(path.dirname(serverBin), { recursive: true });
  log('Building donna-server-go…');
  execSync(`go build -o "${serverBin}" ./cmd/server`, {
    cwd: serverRoot,
    stdio: 'inherit',
    env: { ...process.env, ...env },
  });
}

function spawnTracked(label, command, args, options) {
  const child = spawn(command, args, {
    ...options,
    env: { ...process.env, ...options?.env },
  });
  children.push(child);

  const prefix = `[${label}] `;
  child.stdout?.on('data', (chunk) => process.stdout.write(prefix + chunk));
  child.stderr?.on('data', (chunk) => process.stderr.write(prefix + chunk));
  child.on('exit', (code, signal) => {
    if (!shuttingDown && code !== 0 && signal !== 'SIGTERM') {
      console.error(`[dev:ipad] ${label} exited (${code ?? signal})`);
      shutdown(1);
    }
  });
  return child;
}

function waitForHealth(timeoutMs = 60_000) {
  const url = `http://127.0.0.1:${port}/health`;
  const started = Date.now();

  return new Promise((resolve, reject) => {
    const tick = () => {
      const req = http.get(url, (res) => {
        res.resume();
        if (res.statusCode === 200) {
          resolve();
          return;
        }
        retry();
      });
      req.on('error', retry);
      req.setTimeout(2_000, () => {
        req.destroy();
        retry();
      });
    };

    const retry = () => {
      if (Date.now() - started > timeoutMs) {
        reject(new Error(`Server did not become healthy at ${url}`));
        return;
      }
      setTimeout(tick, 500);
    };

    tick();
  });
}

function runForeground(command, args, options) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, {
      ...options,
      env: { ...process.env, ...options?.env },
      stdio: 'inherit',
    });
    child.on('error', reject);
    child.on('exit', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`${command} exited with code ${code}`));
    });
  });
}

function shutdown(code = 0) {
  if (shuttingDown) return;
  shuttingDown = true;
  log('Stopping…');
  for (const child of children) {
    child.kill('SIGTERM');
  }
  setTimeout(() => process.exit(code), 300);
}

process.on('SIGINT', () => shutdown(0));
process.on('SIGTERM', () => shutdown(0));

async function main() {
  requireMacOS();
  requireCommand('go', 'Install Go: https://go.dev/dl/');
  requireCommand('node');
  requireCommand('npm');
  requireCommand('pod', 'Install CocoaPods: sudo gem install cocoapods');
  requireCommand('xcrun', 'Install Xcode command-line tools.');

  const env = parseEnvFile(envPath);
  validateEnv(env);
  ensureDependencies();

  const device = pickSimulator(listIpadSimulators(), env);
  log(`Target simulator: ${device.name} (${device.udid})`);
  bootSimulator(device);

  syncAppEnv();

  log('');
  log('Voice backend (simulator → host loopback):');
  log(`  ws://127.0.0.1:${port}/voice`);
  log('Metro bundler: localhost (shared with Simulator)');
  log('');

  buildServer(env);

  spawnTracked('server', serverBin, [], {
    cwd: serverRoot,
    env: { ...process.env, ...env, DONNA_PORT: String(port) },
  });

  log(`Waiting for server on :${port}…`);
  await waitForHealth();
  log('Server healthy.');

  spawnTracked('metro', 'npm', ['start'], {
    cwd: appRoot,
  });

  // Metro needs a moment before Xcode build talks to it.
  await new Promise((r) => setTimeout(r, 3_000));

  log(`Building and launching on ${device.name}…`);
  await runForeground(
    'npx',
    ['react-native', 'run-ios', '--udid', device.udid, '--no-packager'],
    { cwd: appRoot },
  );

  log('');
  log('App installed. Server and Metro are still running.');
  log('Press Ctrl+C to stop.');

  await new Promise(() => {});
}

main().catch((err) => {
  console.error(`[dev:ipad] ${err.message ?? err}`);
  shutdown(1);
});
