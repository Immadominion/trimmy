# Trimmy web glossary

The words every screen uses, in English, Latin American Spanish (es-419),
Brazilian Portuguese (pt-BR) and French (fr). The Flutter app uses the same
core list. Items marked **review** are choices a native speaker should confirm.

## Voice

- Short, friendly, plain. Informal second person: es **tú** (plural
  **ustedes**, never *vosotros*), pt-BR **você**, fr **tu**.
- Same rhythm as the English: headings that end with a period keep it
  ("Your desk." / "Tu escritorio." / "Sua mesa." / "Ton bureau.").
- No em dashes (—) in any language. Use a period, comma, colon or parentheses.
- Curly apostrophes and quotes, as the English uses them: es and pt “ ”,
  fr « » with no-break spaces inside, and the French apostrophe ’.
- French puts a no-break space (written ` ` in the catalogs) before
  `?`, `!`, `:` and `;`.
- Amounts, counts, dates and times are never typed into a translation: they
  arrive as `{placeholders}` already formatted for the reader's region.
- Plurals use ICU `{n, plural, one {…} other {…}}` (Spanish, Portuguese and
  French also have `many` for very large numbers; `other` covers it).
  English strings stay exactly as they were, even where the English never
  pluralized; translations may pluralize properly.

## Never translated

Trimmy, Trims (the points, also in the singular context), Sal, Oracle, Shark,
Wolf, Wall Street, ticker and token symbols (AAPLx, USDC, SOL), issuer legal
names, wallet and token addresses, X (the network), Google, Android, Chrome,
Solana, Privy, Tokens.xyz.

## Core terms (fixed)

| English | es-419 | pt-BR | fr |
| --- | --- | --- | --- |
| stock, share | acción | ação | action |
| company | empresa | empresa | entreprise |
| order | orden | ordem | ordre |
| buy / sell | comprar / vender | comprar / vender | acheter / vendre |
| Practice mode | Práctica | Treino | Entraînement |
| Real mode | Real | Real | Réel |
| practice money | dinero de práctica | dinheiro de treino | argent d’entraînement |
| real money | dinero real | dinheiro real | argent réel |
| Desk (home tab) | Escritorio | Mesa | Bureau |
| Market | Mercado | Mercado | Marché |
| Career | Carrera | Carreira | Carrière |
| Profile | Perfil | Perfil | Profil |
| workday | jornada | expediente | journée |
| assignment | tarea | tarefa | mission |
| Day 3 | Día 3 | Dia 3 | Jour 3 |
| streak | racha | sequência | série |
| intern | practicante | estagiário | stagiaire |
| Rookie | Novato | Novato | Recrue |
| Analyst | Analista | Analista | Analyste |
| Trader | Trader | Trader | Trader |
| Senior Trader | Trader sénior | Trader sênior | Trader senior |
| Partner | Socio | Sócio | Associé |
| Legend | Leyenda | Lenda | Légende |
| holdings | tus inversiones | seus investimentos | tes placements (**review**, see below) |
| tokenized stock | acción tokenizada | ação tokenizada | action tokenisée |
| wallet | billetera | carteira | portefeuille |
| add money | agregar dinero | adicionar dinheiro | ajouter de l’argent |
| send | enviar | enviar | envoyer |
| fee | comisión | taxa | frais |
| quote | cotización | cotação | cotation |
| reason (why you bought) | motivo | motivo | raison |
| Wall Street | Wall Street | Wall Street | Wall Street |

## Added for the web (keep consistent)

| English | es-419 | pt-BR | fr | Notes |
| --- | --- | --- | --- | --- |
| paper (unit after an amount: “100.00 paper”) | 100.00 de práctica | 100,00 de treino | 100,00 d’entraînement | **review**: the English “paper” has no literal equivalent; we name practice money instead |
| paper cash, paper balance | efectivo de práctica, saldo de práctica | dinheiro de treino, saldo de treino | argent d’entraînement, solde d’entraînement | |
| your desk (the player’s space, not the tab) | tu escritorio | sua mesa | ton bureau | |
| token | token | token | token | **review** fr: “jeton” is the official term; the crypto community says “token” |
| position | posición | posição | position | |
| sign in | iniciar sesión | entrar | se connecter | |
| account | cuenta | conta | compte | |
| guest desk | escritorio de invitado | mesa de convidado | bureau invité | |
| Try again | Intentar de nuevo | Tentar de novo | Réessayer | |
| Dismiss | Cerrar | Fechar | Fermer | |
| Unavailable | No disponible | Indisponível | Indisponible | |
| no value mark (English “—”) | – | – | – | en dash, as the no-em-dash rule asks |
| large numbers, short form | 1.2 mil, 3.4 M, 1.2 mil M, 1.5 B | 1,2 mil, 3,4 mi, 1,2 bi, 1,5 tri | 1,2 k, 3,4 M, 1,2 Md, 1,5 Bn | same units as the Flutter app |
| US dollars | US$ | US$ | $US | placed per region: US$1,234.56 (es-419, es-MX), US$ 1.234,56 (es-AR, pt-BR), 1 234,56 $US (fr) |

## Open questions for native review

- **fr “holdings”**: the core list says “vos placements”, but the app speaks
  to the player with **tu**, whose possessive is “tes”. The web uses
  **tes placements**. Confirm, or switch the whole French voice to vous.
- **fr Rookie**: the core list says **Recrue**; the Flutter ARB currently has
  “Débutant”. The web follows the core list.
- **paper as a unit**: “de práctica / de treino / d’entraînement” after an
  amount reads naturally in Spanish and Portuguese; French “100,00
  d’entraînement” is understandable but unusual.
- **token in French**: “token” vs “jeton”.
