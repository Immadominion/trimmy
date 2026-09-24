/// The fictional claims available when preparing Aster's company update.
/// This authored order also defines stable saved choice IDs and Journal order.
class UpdateFact {
  const UpdateFact({
    required this.id,
    required this.text,
    required this.sourceLabel,
    this.detail,
  });

  final String id;
  final String text;
  final String sourceLabel;
  final String? detail;
}

const updateFacts = <UpdateFact>[
  UpdateFact(
    id: 'dated-growth',
    text: 'In 2025, users grew 80%.',
    sourceLabel: 'User report',
    detail: '100,000 users in 2024 became 180,000 in 2025.',
  ),
  UpdateFact(
    id: 'lower-profit',
    text: r'In 2025, profit fell from $400 to $200.',
    sourceLabel: 'Sales and costs',
    detail: 'Subtract costs from sales in each period to compare profit.',
  ),
  UpdateFact(
    id: 'trial-result',
    text: '8 of 10 beta testers liked Aster.',
    sourceLabel: 'Trial replies',
    detail:
        'Eight invited testers liked it; two did not. Other customers were not asked.',
  ),
  UpdateFact(
    id: 'current-growth',
    text: 'In 2026, users grew 80%.',
    sourceLabel: 'User report',
    detail:
        'The report compares 2024 with 2025. It contains no 2026 growth result.',
  ),
  UpdateFact(
    id: 'all-customers',
    text: 'Everyone who uses Aster likes it.',
    sourceLabel: 'Trial replies',
    detail:
        'Two testers did not like it, and the trial did not ask every customer.',
  ),
];

const updateCorrectChoiceId = 'dated-growth+lower-profit+trial-result';

/// The ten three-fact combinations, always in the authored order above.
const updateChoiceIds = <String>[
  updateCorrectChoiceId,
  'dated-growth+lower-profit+current-growth',
  'dated-growth+lower-profit+all-customers',
  'dated-growth+trial-result+current-growth',
  'dated-growth+trial-result+all-customers',
  'dated-growth+current-growth+all-customers',
  'lower-profit+trial-result+current-growth',
  'lower-profit+trial-result+all-customers',
  'lower-profit+current-growth+all-customers',
  'trial-result+current-growth+all-customers',
];

/// Missing facts are unselected. Explicit exclusions remain useful draft state
/// but never participate in the composed choice's identity.
String? updateChoiceId(Map<String, String> parts) {
  if (parts.entries.any(
    (entry) =>
        !updateFacts.any((fact) => fact.id == entry.key) ||
        (entry.value != 'included' && entry.value != 'excluded'),
  )) {
    return null;
  }
  final chosen = updateFacts.where((fact) => parts[fact.id] == 'included');
  if (chosen.length != 3) return null;
  return chosen.map((fact) => fact.id).join('+');
}

/// Decode only recognized canonical choices, preserving first-submission order
/// independently of the sequence in which someone tapped the facts.
List<UpdateFact> updateChoiceFacts(String choiceId) {
  if (!updateChoiceIds.contains(choiceId)) {
    throw ArgumentError.value(choiceId, 'choiceId');
  }
  final ids = choiceId.split('+').toSet();
  return List.unmodifiable(updateFacts.where((fact) => ids.contains(fact.id)));
}
