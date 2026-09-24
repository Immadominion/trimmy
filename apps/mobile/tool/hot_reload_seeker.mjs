// Reuse VS Code's existing Flutter run. No rebuild, launch or focus change.
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
const project = resolve(fileURLToPath(new URL('..', import.meta.url)));
const processes = execFileSync('ps', ['-axo', 'command'], { encoding: 'utf8' });
const uris = [...new Set([...processes.matchAll(/--dtd-uri\s+(ws:\/\/127\.0\.0\.1:\d+\/[^\s]+)/g)].map(m => m[1]))];
function call(uri, method, params = {}) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(uri);
    const timer = setTimeout(() => { ws.close(); reject(new Error('Editor request timed out')); }, 25000);
    ws.onopen = () => ws.send(JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }));
    ws.onerror = () => { clearTimeout(timer); reject(new Error('Editor connection failed')); };
    ws.onmessage = ({data}) => {
      const message = JSON.parse(data);
      if (message.id !== 1) return;
      clearTimeout(timer); ws.close();
      if (message.error) reject(new Error(message.error.message)); else resolve(message.result);
    };
  });
}
let found = false;
for (const uri of uris) {
  let sessions;
  try { sessions = await call(uri, 'Editor.getDebugSessions'); } catch { continue; }
  const session = sessions.debugSessions?.find(s => s.flutterDeviceId === 'SM02G40619141343' && s.projectRootPath === project);
  if (!session) continue;
  await call(uri, process.argv.includes('--restart') ? 'Editor.hotRestart' : 'Editor.hotReload', { debugSessionId: session.id });
  console.log('Reload/restart completed through the existing Seeker editor session.');
  found = true; break;
}
if (!found) { console.error('No matching Seeker editor session. Start Trimmy Seeker (Actual App) in VS Code.'); process.exitCode = 1; }
