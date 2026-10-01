# Trimmy translation glossary

Trimmy speaks English, Latin American Spanish (es-419, `app_es.arb`),
Brazilian Portuguese (pt-BR, `app_pt.arb`) and French (`app_fr.arb`). The web
app uses the same terms, so change a term here and in the web glossary
together.

## Voice

- Short, friendly and plain, like the English. A beginner is reading.
- Informal second person: Spanish "tú", Brazilian Portuguese "você", French
  "tu".
- Sentence case for titles and buttons in every language ("Ajouter de
  l'argent", never "Ajouter De L'Argent").
- No em dashes (—) anywhere. Use a comma, a period or a colon.
- Avoid gendered words about the player where a neutral phrasing exists
  ("Te damos la bienvenida", "Boas-vindas", "Bienvenue").
- French puts a no-break space (U+00A0) before `?`, `!`, `:` and `;`, and
  uses the typographic apostrophe (’). Spanish opens questions and
  exclamations with `¿` and `¡`.
- Amounts, numbers, dates and times are placeholders filled by
  `AppFormats` (`lib/l10n/app_formats.dart`): never write a currency symbol
  or a separator into a message. Every amount is in US dollars: Spanish and
  Portuguese show `US$`, French `$US`.

## Never translated

Trimmy (brand), Trims (the points, a proper noun: "50 Trims"), the
characters Sal, Oracle, Shark and Wolf, Wall Street, ticker and token
symbols (AAPL, AAPLx, USDC, SOL), issuer legal names, wallet addresses,
Solana, and every language's own name in the language picker.

## Core terms

| Term | Meaning | en | es | pt | fr | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| stock / share | A piece of a company | stock, share | acción | ação | action | |
| company | | company | empresa | empresa | entreprise | |
| order | A request to buy or sell | order | orden | ordem | ordre | |
| buy / sell | | buy, sell | comprar, vender | comprar, vender | acheter, vendre | |
| Practice mode | Trading with practice money | Practice, Paper | Práctica | Treino | Entraînement | English says both "Paper" and "Practice"; every translation uses the one term. |
| Real mode | Trading with real money | Real | Real | Real | Réel | |
| practice money | The pretend money for practice | paper, practice money | dinero de práctica | dinheiro de treino | argent d'entraînement | English "paper" (a "paper desk", "500 paper") is always practice money. |
| real money | | real money | dinero real | dinheiro real | argent réel | |
| Desk | Home tab | Desk | Escritorio | Mesa | Bureau | |
| Market | Market tab | Market | Mercado | Mercado | Marché | |
| Career | Career tab | Career | Carrera | Carreira | Carrière | |
| Profile | | Profile | Perfil | Perfil | Profil | |
| workday | One day of assignments from Sal | workday | jornada | expediente | journée | |
| assignment | A task inside a workday | assignment | tarea | tarefa | mission | |
| Day 3 | A workday's number | Day 3 | Día 3 | Dia 3 | Jour 3 | |
| streak | Days in a row | streak | racha | sequência | série | |
| intern | The starting job | intern | practicante | estagiário | stagiaire | |
| ranks | Career levels 1 to 6 | Rookie, Analyst, Trader, Senior Trader, Partner, Legend | Novato, Analista, Trader, Trader sénior, Socio, Leyenda | Novato, Analista, Trader, Trader sênior, Sócio, Lenda | Recrue, Analyste, Trader, Trader senior, Associé, Légende | |
| holdings | What you own | holdings | tus inversiones | seus investimentos | tes placements | French uses "tu" throughout. |
| tokenized stock | A token that tracks a stock | tokenized stock | acción tokenizada | ação tokenizada | action tokenisée | |
| wallet | | wallet | billetera | carteira | portefeuille | |
| deposit / add money | | add money | agregar dinero | adicionar dinheiro | ajouter de l'argent | |
| send | Move money out | send | enviar | enviar | envoyer | |
| fee | | fee | comisión | taxa | frais | French "frais" is plural. |
| quote | A price estimate before an order | quote | cotización | cotação | cotation | |
| reason | Why you bought | reason | motivo | motivo | raison | |
| Wall Street | | Wall Street | Wall Street | Wall Street | Wall Street | Never translated. |
| token | A tokenized stock or coin on Solana | token | token | token | token | French says "token" (masculine), not "jeton". |
| trade (noun) | One buy or sale | trade | operación | operação | opération | |
| trade (verb) | To buy or sell | trade | operar | operar | investir | French may say "passer des ordres"; "trader" only where "investir" reads wrong. A stock "trades": se negocia / é negociada / se négocie. |
| send (noun) | One transfer to another wallet | send | envío | envio | envoi | |
| recipient | The wallet a send goes to | recipient | destinatario | destinatário | destinataire | |
| issuer | The firm that issues a token | issuer | emisor | emissor | émetteur | |
| issuer terms | The terms a buyer accepts | issuer terms | términos del emisor | termos do emissor | conditions de l'émetteur | |
| market maker | A firm that quotes prices | market maker | creador de mercado | formador de mercado | teneur de marché | |
| network fee | Solana's fee, paid in SOL | network fee | comisión de red | taxa de rede | frais de réseau | |
| swap fee | Trimmy's fee on a real order | swap fee | comisión de intercambio | taxa de swap | frais de swap | Native check: Portuguese and French crypto apps say "swap". |
| reminder | The workday nudge | reminder | recordatorio | lembrete | rappel | |
