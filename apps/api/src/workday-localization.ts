import {WORKDAY_TEXTS, type WorkdayLanguage, type WorkdayText} from './workday-texts.generated.js';

/**
 * Serves workdays in the player's language. The database keeps the released
 * structure, ids and English answers; this replaces only text, by id, from the
 * reviewed files in content/workdays/i18n. Answers are checked by id, so a
 * player's answers are checked the same way in every language.
 *
 * English always gets the English edits (hints that no longer give the answer
 * away). Installed apps that send no language keep getting English.
 */
export const WORKDAY_LANGUAGES: readonly WorkdayLanguage[] = Object.freeze(['en', 'es', 'pt', 'fr']);

type Json = Record<string, unknown>;
const record = (value: unknown): Json | null => value && typeof value === 'object' && !Array.isArray(value) ? value as Json : null;

/** The filed hand-off as the database builds it: the required statements, then the player's note. */
function handOff(text: WorkdayText, ids: readonly string[], note: string): string {
  const parts = Object.entries(text.file.parts).filter(([id]) => ids.includes(id)).map(([, value]) => value).join('\n');
  return note.trim() ? `${parts}\n\n${note.trim()}` : parts;
}

function localizeAssignment(item: Json, language: WorkdayLanguage): Json {
  const id = typeof item['id'] === 'string' ? item['id'] : '';
  const text = WORKDAY_TEXTS[language][id], english = WORKDAY_TEXTS.en[id];
  if (!text || !english) return item;
  const out: Json = {...item, title: text.title, brief: text.brief, district: text.district,
    sourceTitle: text.sourceTitle, sourceLabel: text.sourceLabel};
  if (Array.isArray(item['rows'])) out['rows'] = item['rows'].map(row => {
    const r = record(row), t = r && typeof r['id'] === 'string' ? text.rows[r['id']] : undefined;
    return r && t ? {...r, label: t.label, value: t.value, detail: t.detail} : row;
  });
  const evidence = record(item['evidence']);
  if (evidence) out['evidence'] = {...evidence, prompt: text.evidence.prompt};
  const decision = record(item['decision']);
  if (decision) out['decision'] = {...decision, prompt: text.decision.prompt, hint: text.decision.hint,
    ...(Array.isArray(decision['choices']) ? {choices: decision['choices'].map(choice => {
      const c = record(choice), t = c && typeof c['id'] === 'string' ? text.decision.choices[c['id']] : undefined;
      if (!c || !t) return choice;
      // Older APIs sent every choice's feedback; keep that field's presence, in the right language.
      return {...c, label: t.label, ...('feedback' in c ? {feedback: t.feedback} : {})};
    })} : {})};
  const file = record(item['file']);
  if (file) out['file'] = {...file, prompt: text.file.prompt, ...(Array.isArray(file['parts']) ? {parts: file['parts'].map(part => {
    const p = record(part), t = p && typeof p['id'] === 'string' ? text.file.parts[p['id']] : undefined;
    return p && t ? {...p, text: t} : part;
  })} : {})};
  if (typeof item['feedback'] === 'string') out['feedback'] = text.feedback;
  const chosen = record(record(item['answers'])?.['1'])?.['value'];
  if (typeof item['decisionNote'] === 'string' && typeof chosen === 'string' && text.decision.choices[chosen]) {
    out['decisionNote'] = text.decision.choices[chosen].feedback;
  }
  // The note that follows an earlier day's choice, keyed by that choice.
  if (typeof item['contextNote'] === 'string' && text.context) {
    for (const [key, englishNote] of Object.entries(english.context ?? {})) {
      if (englishNote === item['contextNote'] && text.context[key]) out['contextNote'] = text.context[key];
    }
  }
  // The stored hand-off is English text plus the player's note. Rebuild it only when it is exactly that.
  const filed = record(record(item['answers'])?.['2'])?.['ids'];
  if (typeof item['artifact'] === 'string' && Array.isArray(filed) && filed.every(value => typeof value === 'string')) {
    const note = typeof item['draft'] === 'string' ? item['draft'] : '';
    if (handOff(english, filed as string[], note) === item['artifact']) out['artifact'] = handOff(text, filed as string[], note);
  }
  return out;
}

/** The journey with every text in `language`. Unknown shapes pass through unchanged. */
export function localizeJourney(journey: Record<string, unknown>, language: WorkdayLanguage): Record<string, unknown> {
  const assignments = Array.isArray(journey['assignments']) ? journey['assignments'] : null;
  const out: Record<string, unknown> = {...journey};
  if (assignments) out['assignments'] = assignments.map(item => record(item) ? localizeAssignment(item as Json, language) : item);
  const upcoming = record(journey['upcoming']), text = upcoming && typeof upcoming['id'] === 'string' ? WORKDAY_TEXTS[language][upcoming['id']] : undefined;
  if (upcoming && text) out['upcoming'] = {...upcoming, title: text.title, district: text.district};
  return out;
}

/** The feedback for a missed choice, in `language`; the database's English otherwise. */
export function localizeMissFeedback(assignmentId: string, choice: unknown, fallback: string | null, language: WorkdayLanguage): string | null {
  if (fallback === null || typeof choice !== 'string') return fallback;
  return WORKDAY_TEXTS[language][assignmentId]?.decision.choices[choice]?.feedback ?? fallback;
}

/**
 * Typed answers may use a decimal comma ("0,20"): phones in French, Spanish and
 * Portuguese offer only a comma on the decimal pad. The database accepts the
 * decimal point, so a single comma between digits becomes one.
 */
export function normalizeDecimal(value: string): string {
  return /^-?\d{1,9},\d{1,6}$/.test(value) ? value.replace(',', '.') : value;
}
