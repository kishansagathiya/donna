#!/usr/bin/env node
/**
 * Local dev on a USB-connected iPhone:
 *   npm run dev:iphone
 *
 * Starts donna-server-go + Metro, syncs voice host for LAN, builds to device.
 * Optional in .env: DONNA_IOS_DEVICE=<UDID> or device name to pick a device.
 */
import { spawn, execSync } from 'node:child_process';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
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
  console.log(`[dev:iphone] ${msg}`);
}

function fail(msg) {
  console.error(`[dev:iphone] ${msg}`);
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
    fail('Physical iPhone dev requires macOS.');
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

function parseXctraceDevices(output) {
  const devices = [];
  let inDevices = false;
  for (const line of output.split('\n')) {
    if (line.startsWith('== Devices ==')) {
      inDevices = true;
      continue;
    }
    if (line.startsWith('== Simulators ==')) {
      break;
    }
    if (!inDevices) continue;

    const match = line.match(/^(.+?) \([^)]+\) \(([0-9A-Fa-f-]{25,})\)$/);
    if (!match) continue;

    const name = match[1].trim();
    const udid = match[2];
    if (/iPhone|iPad/i.test(name)) {
      devices.push({ name, udid });
    }
  }
  return devices;
}

function parseInstrumentsDevices(output) {
  const devices = [];
  for (const line of output.split('\n')) {
    const match = line.match(/^(.+?) \(([0-9A-Fa-f-]{25,})\)/);
    if (!match) continue;

    const name = match[1].trim();
    const udid = match[2];
    if (/Simulator|Mac/i.test(name)) continue;
    if (/iPhone|iPad/i.test(name)) {
      devices.push({ name, udid });
    }
  }
  return devices;
}

function listPhysicalIOSDevices() {
  const byUdid = new Map();

  try {
    const output = execSync('xcrun xctrace list devices', {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    for (const device of parseXctraceDevices(output)) {
      byUdid.set(device.udid, device);
    }
  } catch {
    // Fall back to instruments below.
  }

  if (byUdid.size === 0) {
    try {
      const output = execSync('xcrun instruments -s devices', {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'ignore'],
      });
      for (const device of parseInstrumentsDevices(output)) {
        byUdid.set(device.udid, device);
      }
    } catch {
      fail('Could not list devices — is Xcode installed?');
    }
  }

  return [...byUdid.values()];
}

function pickDevice(devices, fileEnv) {
  const preferred = (
    process.env.DONNA_IOS_DEVICE ?? fileEnv.DONNA_IOS_DEVICE
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
        `No connected device matches DONNA_IOS_DEVICE="${preferred}". Connected: ${devices.map((d) => `${d.name} (${d.udid})`).join(', ') || '(none)'}`,
      );
    }
    return hit;
  }

  if (devices.length === 0) {
    fail(
      'No physical iPhone/iPad detected. Plug in your device, unlock it, trust this Mac, then retry.',
    );
  }
  if (devices.length === 1) {
    return devices[0];
  }

  log(`Multiple devices — using ${devices[0].name}. Set DONNA_IOS_DEVICE to override.`);
  return devices[0];
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

function readSyncedVoiceHost() {
  const generated = path.join(appRoot, 'src', 'env.generated.ts');
  const text = fs.readFileSync(generated, 'utf8');
  const match = text.match(/ENV_VOICE_DEV_HOST = (.+?) as/);
  if (!match) return null;
  const raw = match[1].trim();
  if (raw === 'null') return null;
  return JSON.parse(raw);
}

function lanIp() {
  try {
    const ip = execSync('ipconfig getifaddr en0', {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    if (ip) return ip;
  } catch {
    // Wi‑Fi may be on another interface
  }

  for (const nets of Object.values(os.networkInterfaces())) {
    for (const net of nets ?? []) {
      if (net.family === 'IPv4' && !net.internal) {
        return net.address;
      }
    }
  }
  return '127.0.0.1';
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
      console.error(`[dev:iphone] ${label} exited (${code ?? signal})`);
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

  const env = parseEnvFile(envPath);
  validateEnv(env);
  ensureDependencies();

  const device = pickDevice(listPhysicalIOSDevices(), env);
  log(`Target device: ${device.name} (${device.udid})`);

  syncAppEnv();
  const voiceHost = readSyncedVoiceHost();
  const packagerHost = lanIp();

  log('');
  log('Voice backend (device):');
  log(`  ws://${voiceHost ?? packagerHost}:${port}/voice`);
  log(`Metro bundler host: ${packagerHost}`);
  log('iPhone and Mac must be on the same Wi‑Fi for voice + Metro.');
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
    env: {
      REACT_NATIVE_PACKAGER_HOSTNAME: packagerHost,
    },
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
  console.error(`[dev:iphone] ${err.message ?? err}`);
  shutdown(1);
});
