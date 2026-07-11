/**
 * Notification Audit Script
 * 
 * Analyzes the orders controller to find which order status transitions
 * send push notifications and to whom.
 * 
 * Run: npx tsx scripts/audit_notifications.ts
 */

import * as fs from 'fs';
import * as path from 'path';

const controllerPath = path.join(__dirname, '..', 'src', 'controllers', 'orders.controller.ts');
const source = fs.readFileSync(controllerPath, 'utf8');

function extractExports(source: string): Map<string, { start: number; end: number }> {
  const exports = new Map<string, { start: number; end: number }>();

  const regex = /export\s+const\s+(\w+)\s*=\s*async\s*\(/g;
  let match;

  while ((match = regex.exec(source)) !== null) {
    const name = match[1];
    const start = match.index;

    let braceCount = 0;
    let end = start;
    let foundOpen = false;

    for (let i = start; i < source.length; i++) {
      if (source[i] === '{') { foundOpen = true; braceCount++; }
      else if (source[i] === '}') { braceCount--; if (foundOpen && braceCount === 0) { end = i + 1; break; } }
    }

    exports.set(name, { start, end });
  }

  return exports;
}

/**
 * Extract all notifyUser() calls from a function body.
 * Returns an array of { target, title } where target is a human-readable
 * description of who receives the notification.
 */
function extractNotificationCalls(body: string): { target: string; title: string }[] {
  const results: { target: string; title: string }[] = [];

  // Find all notifyUser( calls
  const callStarts: number[] = [];
  const re = /notifyUser\(/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(body)) !== null) {
    callStarts.push(m.index);
  }

  for (const startIdx of callStarts) {
    // The first argument is everything between notifyUser( and the first comma
    // that follows the complete first arg (accounting for nested parentheses)
    let parenDepth = 1;
    let firstArgEnd = startIdx + 11; // after 'notifyUser('
    while (parenDepth > 0 && firstArgEnd < body.length) {
      const c = body[firstArgEnd];
      if (c === '(') parenDepth++;
      else if (c === ')') parenDepth--;
      else if (c === ',' && parenDepth === 1) break; // end of first arg
      firstArgEnd++;
    }
    const firstArg = body.substring(startIdx + 11, firstArgEnd).trim();

    // Now find the title by scanning forward to the nearest title: '...'
    const titleMatch = body.substring(startIdx, startIdx + 300).match(/title:\s*'([^']+)'/);
    const title = titleMatch ? titleMatch[1] : '(unknown)';

    // Map the first argument to a human-readable target
    let target = firstArg;
    if (firstArg === 'updated.user_id' || firstArg === 'updated?.user_id') target = 'customer';
    else if (firstArg === 'riderId') target = 'rider';
    else if (firstArg.includes('restaurant.user_id')) target = 'owner';
    else if (firstArg.includes('app.user_id')) target = 'owner';
    else if (firstArg.includes('order.user_id') || firstArg === 'order?.user_id') target = 'customer';
    else if (firstArg.includes('conversation.user_id')) target = 'customer';

    results.push({ target, title });
  }

  return results;
}

const exports = extractExports(source);

console.log('\n🔍 NOTIFICATION AUDIT REPORT');
console.log('═══════════════════════════════\n');

type AuditEntry = {
  functionName: string;
  statusTransition: string;
  notifyUserCalls: number;
  hasNotifyUser: boolean;
  notifiedParties: string[];
};

const results: AuditEntry[] = [];

for (const [name, { start, end }] of exports) {
  const body = source.substring(start, end);

  // Find status transition
  const statusMatch = body.match(/status:\s*'([A-Z_]+)'/);
  const statusFrom = body.match(/\.in\(['"]status['"],\s*\[([^\]]+)\]/);

  let statusTransition = '';
  if (statusMatch) {
    const toStatus = statusMatch[1];
    const fromStatus = statusFrom
      ? statusFrom[1].replace(/'/g, '').replace(/,/g, ' | ')
      : '(any)';
    statusTransition = `${fromStatus} → ${toStatus}`;
  } else {
    statusTransition = '(no status change)';
  }

  const calls = extractNotificationCalls(body);

  results.push({
    functionName: name,
    statusTransition,
    notifyUserCalls: calls.length,
    hasNotifyUser: calls.length > 0,
    notifiedParties: calls.map(c => `${c.target} ("${c.title}")`),
  });
}

// Print table
console.log('  ' + 'Function'.padEnd(28) + 'Status Transition'.padEnd(35) + 'Notified?'.padEnd(12) + 'Party');
console.log('  ' + '─'.repeat(100));
for (const r of results) {
  const status = r.hasNotifyUser ? '✅ YES' : '❌ MISSING';
  const parties = r.notifiedParties.length > 0 ? r.notifiedParties.join(', ') : '—';
  console.log(`  ${r.functionName.padEnd(26)} ${r.statusTransition.padEnd(33)} ${status.padEnd(10)} ${parties}`);
}

console.log('\n\n📋 SUMMARY');
console.log('─────────────────');
const missing = results.filter(r => !r.hasNotifyUser);
const hasNotify = results.filter(r => r.hasNotifyUser);
console.log(`  Total endpoints: ${results.length}`);
console.log(`  ✅ Send notifications: ${hasNotify.length}`);
console.log(`  ❌ Missing: ${missing.length}`);

if (missing.length > 0) {
  console.log('\n  Missing in:');
  for (const m of missing) {
    console.log(`    • ${m.functionName} (${m.statusTransition})`);
  }
}
console.log();
