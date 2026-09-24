import 'package:flutter/foundation.dart';

enum JourneyStepKind { intro, decision, reflection }

@immutable
class JourneyChoice {
  const JourneyChoice({required this.label, required this.feedback});
  final String label;
  final String feedback;
}

@immutable
class JourneyStep {
  const JourneyStep({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    this.question = '',
    this.choices = const [],
  });
  final String id;
  final JourneyStepKind kind;
  final String title;
  final String body;
  final String question;
  final List<JourneyChoice> choices;
}

@immutable
class JourneyChapter {
  const JourneyChapter({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.steps,
  });
  final String id;
  final String title;
  final String subtitle;
  final List<JourneyStep> steps;
}

@immutable
class JourneySession {
  JourneySession({
    required this.chapterId,
    this.stepIndex = 0,
    Map<String, int> answers = const {},
    this.reflection = '',
  }) : answers = Map.unmodifiable(answers);
  final String chapterId;
  final int stepIndex;
  final Map<String, int> answers;
  final String reflection;

  JourneySession copyWith({
    int? stepIndex,
    Map<String, int>? answers,
    String? reflection,
  }) => JourneySession(
    chapterId: chapterId,
    stepIndex: stepIndex ?? this.stepIndex,
    answers: answers ?? this.answers,
    reflection: reflection ?? this.reflection,
  );

  Map<String, Object> toJson() => {
    'chapterId': chapterId,
    'stepIndex': stepIndex,
    'answers': answers,
    'reflection': reflection,
  };
}

@immutable
class JourneyCompletion {
  const JourneyCompletion({
    required this.chapterId,
    required this.reflection,
    required this.completedAt,
  });
  final String chapterId;
  final String reflection;
  final DateTime completedAt;

  Map<String, String> toJson() => {
    'chapterId': chapterId,
    'reflection': reflection,
    'completedAt': completedAt.toUtc().toIso8601String(),
  };
}

// Original fictional scenarios. Questions teach reasoning, not stock selection.
// Background concepts checked against these primary sources on 2026-09-13:
// https://www.investor.gov/introduction-investing/getting-started/understanding-fees
// https://www.investor.gov/introduction-investing/getting-started/asset-allocation
// https://www.investor.gov/introduction-investing/getting-started/researching-investments
const firstFloorChapter = JourneyChapter(
  id: 'first-floor',
  title: 'The first floor',
  subtitle: 'A business, a bill, and a bigger picture.',
  steps: [
    JourneyStep(
      id: 'welcome',
      kind: JourneyStepKind.intro,
      title: 'Pull up a chair.',
      body:
          'Ada slides three folders across the desk. “Before anyone has a hot '
          'take, we ask a few ordinary questions.” Nothing here places a trade. '
          'The companies and numbers in these sessions are fictional.',
      question:
          'Today: understand a business, notice a cost, and look beyond one name.',
    ),
    JourneyStep(
      id: 'business-model',
      kind: JourneyStepKind.decision,
      title: 'What keeps the lights on?',
      body:
          'Aster Labs sells a scheduling app. Its downloads doubled, but the '
          'office note says most new users chose the free plan.',
      question: 'What would help explain how Aster makes money?',
      choices: [
        JourneyChoice(
          label: 'How many users pay, and what it costs to serve them',
          feedback:
              'Useful. Paying customers connect usage to revenue. Costs '
              'help explain whether that revenue can support the business. '
              'Neither number alone tells you what a stock is worth.',
        ),
        JourneyChoice(
          label: 'Whether its logo looks more polished this year',
          feedback:
              'A good logo may help a brand, but it does not show who pays '
              'or what the service costs to run. Ada would open those numbers next.',
        ),
        JourneyChoice(
          label: 'Which colleague sounds most excited about it',
          feedback:
              'Enthusiasm gives you a question to investigate, not an '
              'answer. Ask what customers pay for and what evidence supports the story.',
        ),
      ],
    ),
    JourneyStep(
      id: 'fees',
      kind: JourneyStepKind.decision,
      title: 'Read the small bill.',
      body:
          'A fictional purchase uses a \$20 budget. A clearly disclosed \$1 '
          'charge is taken from that budget before the purchase. Ignore every '
          'other cost for this example.',
      question: 'How much of the budget reaches the position?',
      choices: [
        JourneyChoice(
          label: r'$20: the charge is just a label',
          feedback:
              'The charge comes from the same budget, so it leaves less '
              'to purchase the position. In this example, \$20 minus \$1 is \$19.',
        ),
        JourneyChoice(
          label: r'$19: the charge uses part of the budget',
          feedback:
              'Exactly: \$19 reaches the position. The \$1 charge is 5% '
              'of the starting budget. Real quotes can have other costs, so read '
              'the full breakdown rather than assuming this example is a quote.',
        ),
        JourneyChoice(
          label: r'$21: the charge increases the holding',
          feedback:
              'A charge is an expense here, not extra money invested. '
              'The stated \$20 budget becomes a \$19 purchase after the \$1 charge.',
        ),
      ],
    ),
    JourneyStep(
      id: 'diversification',
      kind: JourneyStepKind.decision,
      title: 'Three names, one weather forecast.',
      body:
          'Remy points to three fictional airlines. “Different names. '
          'Completely different risks?” All three spend heavily on fuel.',
      question: 'What does this collection still have in common?',
      choices: [
        JourneyChoice(
          label: 'Nothing. Three names remove every shared risk',
          feedback:
              'Different names can still share an industry and common '
              'pressures. A fuel-price shock could affect all three. '
              'Diversification never removes every risk.',
        ),
        JourneyChoice(
          label: 'They must always move by exactly the same amount',
          feedback:
              'Shared pressures do not make companies identical. '
              'Their costs, routes and finances may differ, even when the same '
              'event affects the whole industry.',
        ),
        JourneyChoice(
          label: 'Exposure to the airline business and fuel costs',
          feedback:
              'Right. Count the risks behind the names. Spreading '
              'exposure can reduce concentration, but it cannot guarantee '
              'a gain or prevent losses.',
        ),
      ],
    ),
    JourneyStep(
      id: 'reflection',
      kind: JourneyStepKind.reflection,
      title: 'Leave yourself a useful note.',
      body:
          'Ada taps the empty line at the bottom of the page. “A question '
          'you can explain is worth keeping.”',
      question:
          'What would you check before deciding whether you understand a position?',
    ),
  ],
);

const readTheRoomChapter = JourneyChapter(
  id: 'read-the-room',
  title: 'Read the room',
  subtitle: 'Separate a strong story from strong evidence.',
  steps: [
    JourneyStep(
      id: 'welcome',
      kind: JourneyStepKind.intro,
      title: 'The meeting is getting loud.',
      body:
          'Jules has a headline. Remy has a chart. Ada wants to know what '
          'either one actually establishes. Three fictional notes are waiting.',
      question:
          'Today: trace a source, read a comparison, and name uncertainty.',
    ),
    JourneyStep(
      id: 'source',
      kind: JourneyStepKind.decision,
      title: 'Who said what?',
      body:
          'A post says fictional Northline will “double sales next month.” '
          'It links to another post, which links to no company statement.',
      question: 'What is the most useful next step?',
      choices: [
        JourneyChoice(
          label: 'Find the original evidence and its date',
          feedback:
              'Yes. Trace the statement to a verifiable source and check '
              'what period it covers. Even a company forecast is an estimate, '
              'not a promise.',
        ),
        JourneyChoice(
          label: 'Treat the number of reposts as confirmation',
          feedback:
              'Repetition can spread the same unsupported claim. '
              'Popularity does not supply missing evidence or a publication date.',
        ),
        JourneyChoice(
          label: 'Assume a precise number must be accurate',
          feedback:
              'Precision is a way of writing a claim. It is not evidence '
              'that the claim was measured well or will happen.',
        ),
      ],
    ),
    JourneyStep(
      id: 'comparison',
      kind: JourneyStepKind.decision,
      title: 'The same climb?',
      body:
          'In a fictional example, one price goes from \$10 to \$11. Another '
          'goes from \$100 to \$101. Both rise by one dollar. Ignore costs.',
      question: 'How do the percentage changes compare?',
      choices: [
        JourneyChoice(
          label: 'Both rose 1%',
          feedback:
              'A dollar is a different share of each starting price. '
              'Divide the change by the starting value: 1 ÷ 10 is 10%; '
              '1 ÷ 100 is 1%.',
        ),
        JourneyChoice(
          label: 'The first rose 10%; the second rose 1%',
          feedback:
              'Correct. Percentage change makes this particular '
              'comparison clearer. It still does not tell you which position '
              'will perform better next.',
        ),
        JourneyChoice(
          label: 'The second rose more because its price is higher',
          feedback:
              'A higher share price does not turn the same dollar '
              'change into a larger percentage. Here the first change is 10% '
              'and the second is 1%.',
        ),
      ],
    ),
    JourneyStep(
      id: 'uncertainty',
      kind: JourneyStepKind.decision,
      title: 'One page is missing.',
      body:
          'Northline reports growing sales, but the note on your desk '
          'does not show its expenses, debt or cash position.',
      question: 'Which note is faithful to what you know?',
      choices: [
        JourneyChoice(
          label: 'Growing sales prove this business cannot struggle',
          feedback:
              'Sales tell one part of the story. Expenses, debt and '
              'cash can change the picture. A missing page is a reason to '
              'investigate, not a reason to assume the best.',
        ),
        JourneyChoice(
          label: 'Missing information proves the business is failing',
          feedback:
              'Missing evidence does not prove either success or '
              'failure. Name what is missing and look for reliable information.',
        ),
        JourneyChoice(
          label: 'Sales grew; I still need to understand costs and finances',
          feedback:
              'That keeps the fact separate from the open question. '
              'You can be interested in a story while staying clear about '
              'what you have not established.',
        ),
      ],
    ),
    JourneyStep(
      id: 'reflection',
      kind: JourneyStepKind.reflection,
      title: 'Write the quieter sentence.',
      body: '“The loudest sentence is rarely the most careful one,” Ada says.',
      question:
          'What is one question you would ask when a confident investing claim crosses your feed?',
    ),
  ],
);

const longViewChapter = JourneyChapter(
  id: 'the-long-view',
  title: 'The long view',
  subtitle: 'Give time, risk and your reasoning a place at the desk.',
  steps: [
    JourneyStep(
      id: 'welcome',
      kind: JourneyStepKind.intro,
      title: 'Stay for the closing note.',
      body:
          'The office is quieter. Ada opens the notebook from an earlier '
          'session. “What changed? What did we learn? Those are different questions.”',
      question:
          'Today: distinguish a deadline, a result, and a changed assumption.',
    ),
    JourneyStep(
      id: 'time-horizon',
      kind: JourneyStepKind.decision,
      title: 'The calendar matters.',
      body:
          'A fictional character has a fixed bill due next week and a '
          'separate goal years away. They ask whether those deadlines are '
          'irrelevant to risk.',
      question: 'What should their reasoning acknowledge?',
      choices: [
        JourneyChoice(
          label:
              'A short deadline leaves less room for a loss or delayed access',
          feedback:
              'Yes. Timing and the need to access money matter. A '
              'near-term obligation and a distant goal call for different '
              'questions; this exercise does not choose an investment for anyone.',
        ),
        JourneyChoice(
          label: 'A good story makes any deadline irrelevant',
          feedback:
              'A compelling story cannot move a bill or guarantee '
              'when money can be recovered. Deadlines are part of the context.',
        ),
        JourneyChoice(
          label: 'A longer deadline guarantees a positive return',
          feedback:
              'More time does not guarantee a gain. It changes the '
              'context in which someone considers uncertainty and access.',
        ),
      ],
    ),
    JourneyStep(
      id: 'outcomes',
      kind: JourneyStepKind.decision,
      title: 'A result is not the whole review.',
      body:
          'Remy made a prediction from an unsupported rumor. By chance, '
          'the fictional price moved in the predicted direction.',
      question: 'What is useful to record?',
      choices: [
        JourneyChoice(
          label: 'The result proves the rumor was reliable',
          feedback:
              'One matching result does not validate an unsupported '
              'source. Record the result, but also examine the reasoning '
              'that led to the prediction.',
        ),
        JourneyChoice(
          label: 'The outcome and the weakness of the original evidence',
          feedback:
              'That separates what happened from how the decision '
              'was made. A review can improve your process even when '
              'luck produced a pleasing result.',
        ),
        JourneyChoice(
          label: 'Only results matter, so the original note can be deleted',
          feedback:
              'Keeping the original note lets you compare your '
              'expectations with events. Rewriting history makes learning '
              'harder, even when the outcome felt good.',
        ),
      ],
    ),
    JourneyStep(
      id: 'assumptions',
      kind: JourneyStepKind.decision,
      title: 'A reason to look again.',
      body:
          'Your fictional note assumed Aster would keep its largest '
          'customer. A later company update says that customer has left.',
      question: 'What does the new information justify?',
      choices: [
        JourneyChoice(
          label: 'Ignoring it so the original story stays tidy',
          feedback:
              'A tidy story is not the goal. When evidence challenges '
              'an assumption, record that change and reconsider the reasoning.',
        ),
        JourneyChoice(
          label: 'Treating any new headline as an automatic trade instruction',
          feedback:
              'New information deserves attention, but a headline '
              'alone is not a personalized instruction to transact. '
              'First understand what changed and what remains uncertain.',
        ),
        JourneyChoice(
          label: 'Revisiting the assumption and writing down what changed',
          feedback:
              'Exactly. A useful notebook can change its mind with '
              'evidence. Updating an explanation is progress; it does '
              'not require a trade.',
        ),
      ],
    ),
    JourneyStep(
      id: 'reflection',
      kind: JourneyStepKind.reflection,
      title: 'A note worth returning to.',
      body:
          'Ada closes the folder. “Keep a reason you can revisit, '
          'not just a prediction you want to defend.”',
      question:
          'What would make you revisit an explanation you currently believe?',
    ),
  ],
);

const journeyChapters = [
  firstFloorChapter,
  readTheRoomChapter,
  longViewChapter,
];

JourneyChapter? journeyChapterById(String id) {
  for (final chapter in journeyChapters) {
    if (chapter.id == id) return chapter;
  }
  return null;
}
