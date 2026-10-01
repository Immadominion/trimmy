#!/usr/bin/env node
/**
 * Trimmy product metrics: a read-only report of how players arrive, whether
 * they come back, and how the weekday desk is used.
 *
 *   node tool/runtime/product-metrics.mjs [--days 28] [--json]
 *
 * Connects like apply-migrations.mjs (TRIMMY_MIGRATION_DATABASE_URL and the
 * optional TRIMMY_MIGRATION_DATABASE_CA_FILE) and runs every query inside a
 * READ ONLY transaction in UTC, so it can never change data.
 *
 * Two sources, kept apart on purpose:
 *  - What the server already records (career activity, filed workdays, orders,
 *    wallets, sends). This is the truth for retention and the weekday desk, and
 *    it covers players from before the apps sent any events.
 *  - First-party app events (migration 0039): the first-run funnel, why the app
 *    was opened, the tab in view and failed launches. These exist only from the
 *    app versions that send them.
 * A player's "active day" is a UTC day with career activity, a live order, or
 * an app open from an install linked to them.
 */
import {readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import pg from 'pg';
import {parseOwnerDatabaseUrl} from './apply-migrations.mjs';

export const FUNNEL_STEPS = ['welcome', 'note', 'first_trade', 'review', 'first_order', 'celebration', 'gate', 'reminders', 'next_move', 'home'];

/** The report's queries. Each takes $1 = window start and $2 = report time. */
export const QUERIES = Object.freeze({
  overview: `SELECT
    (SELECT count(*) FROM trimmy.users WHERE created_at >= $1)::int AS new_users,
    (SELECT count(*) FROM trimmy.guest_sessions WHERE created_at >= $1)::int AS new_guest_desks,
    (SELECT count(*) FROM trimmy.guest_sessions WHERE claimed_at >= $1)::int AS guest_desks_saved,
    (SELECT count(DISTINCT user_id) FROM trimmy.career_activity_events WHERE observed_at >= $1)::int AS active_players,
    (SELECT count(DISTINCT install_id) FROM trimmy.product_events WHERE occurred_at >= $1)::int AS installs_seen,
    (SELECT count(*) FROM trimmy.product_events WHERE occurred_at >= $1)::int AS events`,
  platforms: `SELECT platform, split_part(locale, '-', 1) AS language, count(DISTINCT install_id)::int AS installs
    FROM trimmy.product_events WHERE occurred_at >= $1 GROUP BY 1, 2 ORDER BY 3 DESC, 1, 2`,
  daily: `WITH days AS (SELECT d::date AS day FROM generate_series($1::timestamptz::date, $2::timestamptz::date, interval '1 day') d),
    opens AS (SELECT occurred_at::date AS day, count(DISTINCT install_id)::int AS n FROM trimmy.product_events
      WHERE name = 'app_open' AND occurred_at >= $1 GROUP BY 1),
    players AS (SELECT day, count(DISTINCT user_id)::int AS n FROM (
      SELECT user_id, observed_at::date AS day FROM trimmy.career_activity_events WHERE observed_at >= $1
      UNION ALL SELECT user_id, created_at::date FROM trimmy.live_stock_orders WHERE created_at >= $1) a GROUP BY 1),
    filed AS (SELECT completed_at::date AS day, count(*)::int AS n FROM trimmy.workday_completions WHERE completed_at >= $1 GROUP BY 1)
    SELECT days.day::text AS day, coalesce(opens.n, 0) AS installs_opened, coalesce(players.n, 0) AS players_active, coalesce(filed.n, 0) AS workdays_filed
    FROM days LEFT JOIN opens USING (day) LEFT JOIN players USING (day) LEFT JOIN filed USING (day) ORDER BY days.day`,
  // Installs first seen in the window, and how far each got in its first 7 days.
  funnel: `WITH first_seen AS (SELECT install_id, min(occurred_at) AS first_at FROM trimmy.product_events GROUP BY 1 HAVING min(occurred_at) >= $1),
    steps AS (SELECT DISTINCT e.install_id, e.props->>'step' AS step FROM trimmy.product_events e JOIN first_seen f USING (install_id)
      WHERE e.name = 'onboarding_step' AND e.occurred_at < f.first_at + interval '7 days'),
    linked AS (SELECT DISTINCT l.install_id, l.user_id FROM trimmy.product_install_links l JOIN first_seen f USING (install_id)),
    worked AS (SELECT DISTINCT k.install_id FROM linked k JOIN first_seen f USING (install_id)
      JOIN trimmy.workday_completions c ON c.user_id = k.user_id AND c.completed_at < f.first_at + interval '7 days'),
    returned AS (SELECT DISTINCT e.install_id FROM trimmy.product_events e JOIN first_seen f USING (install_id)
      WHERE e.name = 'app_open' AND e.occurred_at::date > f.first_at::date AND e.occurred_at < f.first_at + interval '7 days')
    SELECT 'installs' AS stage, count(*)::int AS installs FROM first_seen
    UNION ALL SELECT 'step:' || step, count(*)::int FROM steps GROUP BY step
    UNION ALL SELECT 'linked to a desk', count(DISTINCT install_id)::int FROM linked
    UNION ALL SELECT 'filed a workday (7 days)', count(*)::int FROM worked
    UNION ALL SELECT 'came back another day (7 days)', count(*)::int FROM returned`,
  skips: `SELECT props->>'step' AS step, count(DISTINCT install_id)::int AS installs FROM trimmy.product_events
    WHERE name = 'onboarding_skip' AND occurred_at >= $1 GROUP BY 1 ORDER BY 2 DESC`,
  // Weekly cohorts of players by their first active day; a day counts only once it has fully passed.
  retention: `WITH activity AS (
      SELECT user_id, observed_at::date AS day FROM trimmy.career_activity_events
      UNION SELECT user_id, created_at::date FROM trimmy.live_stock_orders
      UNION SELECT l.user_id, e.occurred_at::date FROM trimmy.product_events e JOIN trimmy.product_install_links l USING (install_id) WHERE e.name = 'app_open'),
    first AS (SELECT user_id, min(day) AS first_day FROM activity GROUP BY 1),
    next_desk AS (SELECT f.user_id, f.first_day, (SELECT min(f.first_day + o) FROM generate_series(1, 7) o WHERE trimmy.career_desk_day(f.first_day + o)) AS day FROM first f)
    SELECT date_trunc('week', f.first_day)::date::text AS cohort_week, count(*)::int AS players,
      count(*) FILTER (WHERE f.first_day + 1 < $2::timestamptz::date)::int AS d1_eligible,
      count(*) FILTER (WHERE EXISTS (SELECT 1 FROM activity a WHERE a.user_id = f.user_id AND a.day = f.first_day + 1))::int AS d1,
      count(*) FILTER (WHERE n.day < $2::timestamptz::date)::int AS next_desk_day_eligible,
      count(*) FILTER (WHERE EXISTS (SELECT 1 FROM activity a WHERE a.user_id = f.user_id AND a.day = n.day))::int AS next_desk_day,
      count(*) FILTER (WHERE f.first_day + 7 < $2::timestamptz::date)::int AS w1_eligible,
      count(*) FILTER (WHERE EXISTS (SELECT 1 FROM activity a WHERE a.user_id = f.user_id AND a.day BETWEEN f.first_day + 1 AND f.first_day + 7))::int AS w1,
      count(*) FILTER (WHERE f.first_day + 7 < $2::timestamptz::date)::int AS d7_eligible,
      count(*) FILTER (WHERE EXISTS (SELECT 1 FROM activity a WHERE a.user_id = f.user_id AND a.day = f.first_day + 7))::int AS d7,
      count(*) FILTER (WHERE f.first_day + 30 < $2::timestamptz::date)::int AS d30_eligible,
      count(*) FILTER (WHERE EXISTS (SELECT 1 FROM activity a WHERE a.user_id = f.user_id AND a.day = f.first_day + 30))::int AS d30
    FROM first f JOIN next_desk n USING (user_id) WHERE f.first_day >= $1::timestamptz::date - 56
    GROUP BY date_trunc('week', f.first_day) ORDER BY 1`,
  // The weekday desk: how many players file, how often first try, and whether a filer files again on the next desk day.
  cadence: `WITH filings AS (SELECT user_id, completed_date AS day, trims FROM trimmy.workday_completions WHERE completed_at >= $1),
    days AS (SELECT DISTINCT user_id, day FROM filings),
    nexts AS (SELECT d.user_id, d.day, (SELECT min(d.day + o) FROM generate_series(1, 7) o WHERE trimmy.career_desk_day(d.day + o)) AS next_day FROM days d),
    per_day AS (SELECT date_trunc('week', n.day)::date AS week, count(*)::int AS player_days, count(DISTINCT n.user_id)::int AS filers,
      count(*) FILTER (WHERE n.next_day < $2::timestamptz::date)::int AS repeat_eligible,
      count(*) FILTER (WHERE EXISTS (SELECT 1 FROM days g WHERE g.user_id = n.user_id AND g.day = n.next_day))::int AS filed_next_desk_day
      FROM nexts n GROUP BY 1),
    per_filing AS (SELECT date_trunc('week', day)::date AS week, count(*)::int AS filings, count(*) FILTER (WHERE trims = 20)::int AS first_try
      FROM filings GROUP BY 1)
    SELECT p.week::text AS week, p.player_days, p.filers, f.filings, f.first_try, p.repeat_eligible, p.filed_next_desk_day
    FROM per_day p JOIN per_filing f USING (week) ORDER BY 1`,
  waiting: `SELECT props->>'state' AS state, count(*)::int AS times, count(DISTINCT install_id)::int AS installs
    FROM trimmy.product_events WHERE name = 'workday_waiting' AND occurred_at >= $1 GROUP BY 1 ORDER BY 2 DESC`,
  opens: `SELECT date_trunc('week', occurred_at)::date::text AS week, props->>'source' AS source, count(*)::int AS opens, count(DISTINCT install_id)::int AS installs
    FROM trimmy.product_events WHERE name = 'app_open' AND occurred_at >= $1 GROUP BY 1, 2 ORDER BY 1, 3 DESC`,
  choices: `SELECT name, coalesce(props->>'choice', props->>'frequency', props->>'enabled', props->>'to', props->>'action', props->>'language', props->>'tab') AS value,
      coalesce(props->>'permission', '') AS permission, count(DISTINCT install_id)::int AS installs, count(*)::int AS times
    FROM trimmy.product_events WHERE occurred_at >= $1 AND name IN ('gate_choice', 'reminder_choice', 'push_opt_in', 'mode_switch', 'money_action', 'language_set', 'tab_view')
    GROUP BY 1, 2, 3 ORDER BY 1, 4 DESC`,
  failures: `SELECT props->>'stage' AS stage, platform, count(*)::int AS times, count(DISTINCT install_id)::int AS installs
    FROM trimmy.product_events WHERE name = 'startup_failed' AND occurred_at >= $1 GROUP BY 1, 2 ORDER BY 3 DESC`,
  money: `SELECT
    (SELECT count(*) FROM trimmy.wallet_bindings WHERE created_at >= $1)::int AS wallets_linked,
    (SELECT count(*) FROM (SELECT user_id, min(updated_at) AS first_at FROM trimmy.live_stock_orders WHERE status = 'confirmed' GROUP BY 1) f WHERE f.first_at >= $1)::int AS first_real_orders,
    (SELECT count(*) FROM trimmy.live_stock_orders WHERE status = 'confirmed' AND updated_at >= $1)::int AS confirmed_orders,
    (SELECT count(*) FROM trimmy.live_stock_orders WHERE status IN ('failed', 'expired') AND updated_at >= $1)::int AS unfilled_orders,
    (SELECT count(*) FROM trimmy.wallet_transfers WHERE status = 'confirmed' AND created_at >= $1)::int AS sends`,
});

const pct = (part, whole) => whole > 0 ? `${Math.round(part / whole * 1000) / 10}%` : 'n/a';
function table(rows, columns) {
  if (!rows.length) return '_No data yet._\n';
  const head = `| ${columns.map(([, label]) => label).join(' | ')} |\n| ${columns.map(() => '---').join(' | ')} |\n`;
  return head + rows.map(row => `| ${columns.map(([key, , format]) => format ? format(row) : String(row[key] ?? '')).join(' | ')} |`).join('\n') + '\n';
}
// Dates come back as text (YYYY-MM-DD): the driver would otherwise shift them into the machine's time zone.
const day = value => String(value);

/** Markdown for a report's results. */
export function renderReport(results, {days, at}) {
  const o = results.overview[0] ?? {};
  const steps = new Map(results.funnel.map(row => [row.stage, row.installs]));
  const installs = steps.get('installs') ?? 0;
  const funnelRows = [['installs', 'New installs'], ...FUNNEL_STEPS.map(step => [`step:${step}`, `Reached: ${step.replace('_', ' ')}`]),
    ['linked to a desk', 'Linked to a desk'], ['filed a workday (7 days)', 'Filed a workday in 7 days'], ['came back another day (7 days)', 'Came back another day in 7 days']]
    .map(([key, label]) => ({label, n: steps.get(key) ?? 0}));
  return `# Trimmy product metrics

Window: last ${days} days, to ${at.toISOString().slice(0, 16)} UTC. Days are UTC days. Read-only.

## Overview
${table([o], [['new_users', 'New accounts and guest desks'], ['new_guest_desks', 'Guest desks'], ['guest_desks_saved', 'Guest desks saved to an account'],
    ['active_players', 'Players with career activity'], ['installs_seen', 'Installs sending events'], ['events', 'Events']])}
## Platforms and languages (installs sending events)
${table(results.platforms, [['platform', 'Platform'], ['language', 'Language'], ['installs', 'Installs']])}
## Each day
${table(results.daily, [['day', 'Day', row => day(row.day)], ['installs_opened', 'Installs opened'], ['players_active', 'Players active'], ['workdays_filed', 'Workdays filed']])}
## First run (installs first seen in the window, their first 7 days)
${table(funnelRows, [['label', 'Stage'], ['n', 'Installs'], ['share', 'Of new installs', row => pct(row.n, installs)]])}
Skipped the introduction at: ${results.skips.length ? results.skips.map(row => `${row.step} (${row.installs})`).join(', ') : 'nowhere yet'}.

## Coming back (weekly cohorts by first active day)
"Next desk day" is the first weekday after the first day that is not a US market holiday: the day a new workday opens.
${table(results.retention, [['cohort_week', 'Cohort week', row => day(row.cohort_week)], ['players', 'Players'],
    ['d1', 'Day 1', row => pct(row.d1, row.d1_eligible)], ['next', 'Next desk day', row => pct(row.next_desk_day, row.next_desk_day_eligible)],
    ['w1', 'Any day 1 to 7', row => pct(row.w1, row.w1_eligible)], ['d7', 'Day 7', row => pct(row.d7, row.d7_eligible)], ['d30', 'Day 30', row => pct(row.d30, row.d30_eligible)]])}
## The weekday desk
${table(results.cadence, [['week', 'Week', row => day(row.week)], ['filers', 'Players who filed'], ['filings', 'Workdays filed'],
    ['first_try', 'Filed first try', row => pct(row.first_try, row.filings)], ['repeat', 'Filed again the next desk day', row => pct(row.filed_next_desk_day, row.repeat_eligible)]])}
Found the desk waiting: ${results.waiting.length ? results.waiting.map(row => `${row.state} ${row.times} times by ${row.installs} installs`).join('; ') : 'not yet recorded'}.

## Why the app was opened
${table(results.opens, [['week', 'Week', row => day(row.week)], ['source', 'Source'], ['opens', 'Opens'], ['installs', 'Installs']])}
## Choices
${table(results.choices, [['name', 'Event'], ['value', 'Choice'], ['permission', 'Permission'], ['installs', 'Installs'], ['times', 'Times']])}
## Launches that failed
${table(results.failures, [['stage', 'Where'], ['platform', 'Platform'], ['times', 'Times'], ['installs', 'Installs']])}
## Real money (no amounts)
${table(results.money, [['wallets_linked', 'Wallets linked'], ['first_real_orders', 'Players with a first real order'], ['confirmed_orders', 'Confirmed orders'],
    ['unfilled_orders', 'Failed or expired orders'], ['sends', 'Confirmed sends']])}`;
}

/** Runs every query in one READ ONLY transaction. */
export async function collectMetrics(client, {days = 28, at = new Date()} = {}) {
  if (!Number.isSafeInteger(days) || days < 1 || days > 400) throw new Error('--days must be between 1 and 400.');
  const from = new Date(at.getTime() - days * 86_400_000);
  await client.query('BEGIN READ ONLY');
  try {
    await client.query("SET LOCAL TimeZone = 'UTC'");
    await client.query("SET LOCAL statement_timeout = '60s'");
    const results = {};
    for (const [name, sql] of Object.entries(QUERIES)) results[name] = (await client.query(sql, sql.includes('$2') ? [from, at] : [from])).rows;
    await client.query('COMMIT');
    return results;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  }
}

async function main() {
  const args = process.argv.slice(2);
  let days = 28, json = false;
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--json') json = true;
    else if (args[i] === '--days' && /^\d{1,3}$/.test(args[i + 1] ?? '')) days = Number(args[++i]);
    else throw new Error('Usage: node tool/runtime/product-metrics.mjs [--days 28] [--json]');
  }
  const caFile = process.env['TRIMMY_MIGRATION_DATABASE_CA_FILE'];
  const ca = caFile ? await readFile(caFile, 'utf8') : undefined;
  const config = {...parseOwnerDatabaseUrl(process.env['TRIMMY_MIGRATION_DATABASE_URL'], ca), application_name: 'trimmy-metrics'};
  const client = new pg.Client(config);
  await client.connect();
  try {
    const at = new Date();
    const results = await collectMetrics(client, {days, at});
    process.stdout.write(json ? `${JSON.stringify({days, at, results}, null, 1)}\n` : renderReport(results, {days, at}));
  } finally { await client.end(); }
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  main().catch(error => {
    let password = '';
    try { password = decodeURIComponent(new URL(process.env['TRIMMY_MIGRATION_DATABASE_URL'] ?? '').password); } catch { /* no URL, nothing to redact */ }
    const message = error instanceof Error ? error.message : 'unknown error';
    process.stderr.write(`Metrics failed: ${password ? message.split(password).join('[redacted]') : message}\n`);
    process.exitCode = 1;
  });
}
