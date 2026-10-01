import {DESK_STORY_TEXTS, type DeskStoryLanguage} from './desk-story-texts.generated.js';

/**
 * Serves the daily desk in the player's language. The database keeps the
 * released stories, their ids and choices; this replaces only text, by id,
 * from the reviewed files in content/desk-stories/i18n. A player's choice is
 * the same id in every language. Unknown shapes pass through unchanged.
 */
export const DESK_STORY_LANGUAGES: readonly DeskStoryLanguage[] = Object.freeze(['en', 'es', 'pt', 'fr']);

type Json = Record<string, unknown>;
const record = (value: unknown): Json | null => value && typeof value === 'object' && !Array.isArray(value) ? value as Json : null;

export function localizeDeskShift(shift: Record<string, unknown>, language: DeskStoryLanguage): Record<string, unknown> {
  if (language === 'en') return shift;
  const texts = DESK_STORY_TEXTS[language];
  const out: Json = {...shift};
  const story = record(shift['story']);
  const text = story && typeof story['id'] === 'string' ? texts[story['id']] : undefined;
  if (story && text) {
    out['story'] = {...story, title: text.title, body: text.body,
      ...(Array.isArray(story['choices']) ? {choices: story['choices'].map(choice => {
        const c = record(choice), t = c && typeof c['id'] === 'string' ? text.choices[c['id']] : undefined;
        return c && t ? {...c, label: t.label, outcome: t.outcome, takeaway: t.takeaway} : choice;
      })} : {})};
  }
  if (Array.isArray(shift['history'])) {
    out['history'] = shift['history'].map(item => {
      const h = record(item), t = h && typeof h['caseId'] === 'string' ? texts[h['caseId']] : undefined;
      return h && t ? {...h, title: t.title} : item;
    });
  }
  return out;
}
