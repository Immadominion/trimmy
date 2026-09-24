import 'update_assignment.dart';

/// Authored activity copy. IDs remain stable when visible wording changes.
///
/// These definitions contain no progress, storage, rewards or widget behavior.
/// Private construction keeps their nested collections constant and immutable.
class ActivityDefinition {
  const ActivityDefinition._({
    required this.id,
    required this.title,
    required this.officeDescription,
    required this.intro,
    required this.sourceIntro,
    required this.sourceTitle,
    required this.sourceExplanation,
    required this.draftHeadline,
    required this.correctedHeadline,
    required this.correctChoiceId,
    required this.choices,
    required this.challengeTitle,
    required this.challengeText,
    required this.correctedFeedback,
    required this.successFeedback,
    required this.journalEvidence,
    this.evidence = const [],
    this.presentationOrder = const [],
    this.acceptedChoiceIds = const [],
    this.branchVariants = const {},
  });

  final String id;
  final String title;
  final String officeDescription;
  final String intro;
  final String sourceIntro;
  final String sourceTitle;
  final String sourceExplanation;
  final String draftHeadline;
  final String correctedHeadline;
  final String correctChoiceId;
  final List<ActivityChoice> choices;
  final String challengeTitle;
  final String challengeText;
  final String correctedFeedback;
  final String successFeedback;
  final String journalEvidence;
  final List<ActivityEvidence> evidence;
  final List<String> presentationOrder;
  final List<String> acceptedChoiceIds;
  final Map<String, ActivityBranchVariant> branchVariants;

  /// Most activities have one supported answer. An authored decision can list
  /// several accepted choices when each is defensible and must persist as-is.
  List<String> get effectiveAcceptedChoiceIds =>
      acceptedChoiceIds.isEmpty ? <String>[correctChoiceId] : acceptedChoiceIds;

  /// Stable across restarts, independent of the answer registry's order.
  List<ActivityChoice> get presentedChoices => presentationOrder.isEmpty
      ? choices
      : List.unmodifiable(
          presentationOrder.map(
            (id) => choices.firstWhere((choice) => choice.id == id),
          ),
        );
}

/// Sealed copy for a consequence keyed by an immutable first decision.
/// The key itself lives in the catalog and in ActivityCompletion.
class ActivityBranchVariant {
  const ActivityBranchVariant({
    required this.intro,
    required this.draftHeadline,
    required this.correctedHeadline,
    required this.correctedFeedback,
    required this.successFeedback,
    required this.journalEvidence,
    required this.outcomeTitle,
    required this.officeConsequence,
  });

  final String intro;
  final String draftHeadline;
  final String correctedHeadline;
  final String correctedFeedback;
  final String successFeedback;
  final String journalEvidence;
  final String outcomeTitle;
  final String officeConsequence;
}

/// A bounded, authored source. Practice examples never read live balances.
class ActivityEvidence {
  const ActivityEvidence(this.title, this.rows, this.explanation);
  final String title;
  final List<(String, String)> rows;
  final String explanation;
}

class ActivityChoice {
  const ActivityChoice({
    required this.id,
    required this.label,
    required this.detail,
  });

  final String id;
  final String label;
  final String detail;
}

const checkTheDateActivity = ActivityDefinition._(
  id: 'check-the-date',
  title: 'Check the date',
  officeDescription: 'Check which year a growth figure describes.',
  intro: 'The headline says “this year.” Check the report before you share it.',
  sourceIntro: 'Compare the report’s year with the date on the headline.',
  sourceTitle: 'Aster annual report',
  sourceExplanation:
      'Users rose from 100,000 in 2024 to 180,000 in 2025. '
      'That is 80% growth in 2025. The report was published in February 2026.',
  draftHeadline: 'This year, users grew 80%.',
  correctedHeadline: 'In 2025, users grew 80%.',
  correctChoiceId: 'add-year',
  choices: [
    ActivityChoice(
      id: 'add-year',
      label: 'Add the year',
      detail: 'In 2025, users grew 80%.',
    ),
    ActivityChoice(
      id: 'keep-headline',
      label: 'Keep the headline',
      detail: 'This year, users grew 80%.',
    ),
  ],
  challengeTitle: 'The year needs to be clear.',
  challengeText:
      'The headline is dated September 2026, but the report measures growth '
      'from 2024 to 2025. It does not show how user numbers changed in 2026.',
  correctedFeedback:
      'You checked the report again and added 2025. '
      'The headline now matches the source.',
  successFeedback:
      'You added 2025. The headline now matches the year in the report.',
  journalEvidence:
      'The report compared 100,000 users in 2024 with 180,000 in 2025. '
      'The headline was dated September 2026, so “this year” did not match '
      'the figures.',
);

const salesAndProfitActivity = ActivityDefinition._(
  id: 'sales-and-profit',
  title: 'Sales and profit',
  officeDescription: 'See why higher sales can still mean lower profit.',
  intro:
      'Sales increased. Check the costs before deciding what happened to profit.',
  sourceIntro:
      'Sales are money from selling. Profit is what remains after costs.',
  sourceTitle: 'Aster sales and costs',
  sourceExplanation:
      'All amounts are dollars. In this simplified example, profit equals '
      'sales minus the costs shown.',
  draftHeadline: 'Sales rose by 50%, so profit rose too.',
  correctedHeadline: 'Sales rose by 50%, but profit fell by 50%.',
  correctChoiceId: 'check-costs',
  choices: [
    ActivityChoice(
      id: 'check-costs',
      label: 'Check costs',
      detail: r'Costs rose faster. Profit fell from $400 to $200.',
    ),
    ActivityChoice(
      id: 'sales-mean-profit',
      label: 'Use sales alone',
      detail: 'Sales rose by 50%, so profit must have risen too.',
    ),
  ],
  challengeTitle: 'Higher sales do not always mean higher profit.',
  challengeText:
      r'Sales rose from $1,000 to $1,500. Costs rose from $600 to $1,300. '
      r'After costs, profit fell from $400 to $200. '
      'Compare both before making the claim.',
  correctedFeedback:
      'You checked the costs and corrected the headline. '
      'Profit fell even though sales increased.',
  successFeedback:
      'You checked sales and costs. Sales increased, but the company '
      'kept less money as profit.',
  journalEvidence:
      r'In 2024, sales were $1,000 and costs were $600, leaving $400 profit. '
      r'In 2025, sales were $1,500 and costs were $1,300, leaving $200 profit. '
      'Costs grew more than sales, so profit fell.',
);

const checkTheSampleActivity = ActivityDefinition._(
  id: 'check-the-sample',
  title: 'Check the sample',
  officeDescription: 'See who a survey can actually speak for.',
  intro: '“Everyone” is a big claim. Open the replies and see who was asked.',
  sourceIntro: 'Ten beta testers replied. Tap a reply to read it.',
  sourceTitle: 'Aster product trial',
  sourceExplanation:
      'All ten invited beta testers replied. Eight liked Aster; two did not. Other customers were not asked.',
  draftHeadline: 'Everyone likes Aster.',
  correctedHeadline: '8 of 10 beta testers liked Aster.',
  correctChoiceId: 'eight-of-ten-testers',
  choices: [
    ActivityChoice(
      id: 'eight-of-ten-testers',
      label: '8 of 10 beta testers',
      detail: '8 of 10 beta testers liked Aster.',
    ),
    ActivityChoice(
      id: 'all-testers',
      label: 'All beta testers',
      detail: 'All beta testers liked Aster.',
    ),
    ActivityChoice(
      id: 'eight-of-ten-customers',
      label: '8 of 10 customers',
      detail: '8 of 10 customers liked Aster.',
    ),
    ActivityChoice(
      id: 'all-customers',
      label: 'All customers',
      detail: 'All customers liked Aster.',
    ),
  ],
  challengeTitle: 'Keep the count and the group together.',
  challengeText:
      'Eight of the ten invited beta testers liked Aster. Two did not. These replies describe this trial group; they do not tell us what all customers think.',
  correctedFeedback:
      'You narrowed the claim to eight of the ten beta testers. The headline now says what the replies actually show.',
  successFeedback:
      'You kept both the count and the group. A small trial can tell us about its testers, without speaking for every customer.',
  journalEvidence:
      'All ten invited beta testers replied in September 2026. Eight liked Aster and two did not. Other customers were not asked, so the result describes this trial group.',
);

final prepareTheUpdateActivity = ActivityDefinition._(
  id: 'prepare-the-update',
  title: 'Prepare the update',
  officeDescription: 'Bring your three notes together in a company update.',
  intro:
      'You have checked the figures. Pick three facts for our company update.',
  sourceIntro:
      'Your earlier notes are here. Open each tab to check the evidence.',
  sourceTitle: 'Your Aster notes',
  sourceExplanation:
      'The growth and profit figures describe 2025. The product trial describes ten beta testers in September 2026.',
  draftHeadline: 'What belongs in the company update?',
  correctedHeadline: updateChoiceFacts(
    updateCorrectChoiceId,
  ).map((fact) => fact.text).join(' '),
  correctChoiceId: updateCorrectChoiceId,
  choices: List.unmodifiable([
    for (final id in updateChoiceIds)
      ActivityChoice(
        id: id,
        label: 'Company update',
        detail: updateChoiceFacts(id).map((fact) => fact.text).join('\n\n'),
      ),
  ]),
  challengeTitle: 'Keep each fact within its evidence.',
  challengeText:
      'The annual report covers 2025, and the trial only describes its ten beta testers. Include the fall in profit as well as the growth figure.',
  correctedFeedback:
      'You brought the update back to what the notes support. Your first saved draft and the filed version are in the Journal.',
  successFeedback:
      'You kept the year, the fall in profit and the trial group. The update gives the team all three facts.',
  journalEvidence:
      'The annual report compares 2024 with 2025: users grew from 100,000 to 180,000, while profit fell from \$400 to \$200. In the September 2026 trial, eight of ten invited beta testers liked Aster. These notes do not establish 2026 user growth or what every customer thinks.',
);

const companyValueEvidence = ActivityEvidence(
  'Two fictional companies · same moment',
  [
    ('Aster · price per share', r'$10'),
    ('Aster · shares outstanding', '100'),
    ('Harbor · price per share', r'$5'),
    ('Harbor · shares outstanding', '400'),
  ],
  'Each company has one share class in this example. Multiply the share '
      'price by all outstanding shares to compare their total stock-market values. '
      'This does not tell us which is a better investment.',
);

const feeEvidence = ActivityEvidence(
  'Fictional order estimate · US dollars',
  [
    ('Total budget', r'$10'),
    ('One-time purchase fee', r'$1'),
    ('Amount left for shares', r'$9'),
    ('Price per share', r'$3'),
    ('Shares received', '3'),
  ],
  'The fee comes out of the budget. Assume no spread, tax, price movement '
      'or other purchase charges. Future selling costs are not included. '
      'This is an exercise, not an executable quote.',
);

const concentrationEvidence = ActivityEvidence(
  'Fictional holdings · current values',
  [
    ('Aster · shares bought in January', r'$60'),
    ('Aster · shares bought in June', r'$20'),
    ('Harbor · shares bought in June', r'$20'),
    ('Total', r'$100'),
  ],
  'The two Aster purchases are shares in the same company. Group holdings '
      'by the company they depend on, even when they were bought at different times. '
      'Diversification cannot guarantee against losses.',
);

const compareCompanyValueActivity = ActivityDefinition._(
  id: 'compare-company-value',
  title: 'Compare company value',
  officeDescription: 'Look beyond the price of one share.',
  intro:
      'The team called Harbor the smaller company because one share costs less. Check the whole company.',
  sourceIntro: 'Use both the price and the number of shares.',
  sourceTitle: 'Aster and Harbor',
  sourceExplanation:
      'A lower share price does not establish a lower total stock-market value.',
  draftHeadline: r'Harbor is smaller because its shares cost $5.',
  correctedHeadline:
      r'Harbor’s total stock-market value is $2,000; Aster’s is $1,000.',
  correctChoiceId: 'compare-total-value',
  choices: [
    ActivityChoice(
      id: 'compare-total-value',
      label: 'Compare all the shares',
      detail: r'Harbor: $5 × 400 = $2,000. Aster: $10 × 100 = $1,000.',
    ),
    ActivityChoice(
      id: 'lower-price-means-smaller',
      label: 'Compare one share',
      detail:
          r'$5 is less than $10, so Harbor must have the smaller total value.',
    ),
  ],
  challengeTitle: 'One share is only a piece.',
  challengeText:
      'Harbor has four times as many shares outstanding. Multiply each price by its share count. The resulting market value is not a measure of whether an investment is good value.',
  correctedFeedback:
      'You included the share counts. Harbor has the larger total stock-market value in this example.',
  successFeedback:
      'You checked the price and the share count together. A cheaper single share can belong to a company with a larger market value.',
  journalEvidence:
      r'At the same moment, Aster had 100 shares at $10 each, or $1,000 in total. Harbor had 400 shares at $5 each, or $2,000. This comparison does not establish which company is a better investment.',
  evidence: [companyValueEvidence],
  presentationOrder: ['lower-price-means-smaller', 'compare-total-value'],
);

const countTheFeesActivity = ActivityDefinition._(
  id: 'count-the-fees',
  title: 'Count the fees',
  officeDescription: 'Separate the amount spent from the amount invested.',
  intro:
      'This estimate says ten dollars spent means ten dollars in shares. Follow where the money goes.',
  sourceIntro: 'The purchase fee is included in the total budget.',
  sourceTitle: 'The order estimate',
  sourceExplanation:
      'Spending and investment value are different amounts when fees are charged.',
  draftHeadline: r'I spent $10, so my shares are worth $10.',
  correctedHeadline: r'The $10 budget covers a $1 fee and $9 in shares.',
  correctChoiceId: 'nine-dollars-invested',
  choices: [
    ActivityChoice(
      id: 'nine-dollars-invested',
      label: r'$9 in shares',
      detail: r'$1 pays the fee. The remaining $9 buys 3 shares at $3 each.',
    ),
    ActivityChoice(
      id: 'ten-dollars-invested',
      label: r'$10 in shares',
      detail: r'All $10 spent counts as the value of the shares.',
    ),
  ],
  challengeTitle: 'The fee does not buy a share.',
  challengeText:
      r'Subtract the $1 purchase fee from the $10 budget. That leaves $9, buying three $3 shares. With the share price unchanged, their value is $9 before any future selling costs.',
  correctedFeedback:
      'You separated the fee from the shares. The saved estimate now accounts for the whole budget.',
  successFeedback:
      'You followed all ten dollars: one for the fee and nine for the shares. The amount spent is not the starting value of the holding.',
  journalEvidence:
      r'The fictional estimate has a $10 total budget, a $1 purchase fee and a $3 share price. It buys 3 shares worth $9 at that price. No price movement, spread, tax or other purchase costs are assumed; future selling costs are excluded.',
  evidence: [feeEvidence],
  presentationOrder: ['nine-dollars-invested', 'ten-dollars-invested'],
);

const checkConcentrationActivity = ActivityDefinition._(
  id: 'check-concentration',
  title: 'Check concentration',
  officeDescription: 'Count the companies behind the purchases.',
  intro:
      'Three purchases look like three separate risks. Check which companies are behind them.',
  sourceIntro:
      'Group the two Aster purchases before calculating their share of the total.',
  sourceTitle: 'The practice holdings',
  sourceExplanation: 'Separate purchases can still depend on the same company.',
  draftHeadline:
      'Three purchases spread the money equally across three companies.',
  correctedHeadline: '80% of these holdings is in Aster; 20% is in Harbor.',
  correctChoiceId: 'eighty-percent-aster',
  choices: [
    ActivityChoice(
      id: 'eighty-percent-aster',
      label: '80% is in Aster',
      detail: r'The two Aster purchases total $80 of the $100 holdings.',
    ),
    ActivityChoice(
      id: 'three-equal-companies',
      label: 'Three equal company risks',
      detail:
          'Each purchase is a separate line, so there are three equally weighted companies.',
    ),
  ],
  challengeTitle: 'Two dates, the same company.',
  challengeText:
      r'Both the $60 January purchase and the $20 June purchase depend on Aster. Together they make up $80 of $100, or 80%. The remaining $20 is in Harbor. A count of purchase lines does not measure diversification.',
  correctedFeedback:
      'You grouped the purchases by company. The notes now show how much depends on Aster.',
  successFeedback:
      'You looked through the purchase dates and found the shared company. Most of this example depends on Aster.',
  journalEvidence:
      r'The current values are $60 in the January Aster purchase, $20 in the June Aster purchase and $20 in Harbor. Aster accounts for $80 ÷ $100 = 80%. These are two companies, and diversification does not eliminate the risk of loss.',
  evidence: [concentrationEvidence],
  presentationOrder: ['three-equal-companies', 'eighty-percent-aster'],
);

const prepareTheComparisonActivity = ActivityDefinition._(
  id: 'prepare-the-comparison',
  title: 'Prepare the comparison',
  officeDescription:
      'Bring company value, fees and concentration into one clear note.',
  intro:
      'The team wants a comparison, not a guess about which stock will win. Check your three sources and choose the note they support.',
  sourceIntro:
      'These are three separate practice examples. Keep each conclusion tied to its own figures.',
  sourceTitle: 'Your comparison sources',
  sourceExplanation:
      'Company value, an order estimate and a set of holdings answer different questions.',
  draftHeadline: 'What can we say from these three examples?',
  correctedHeadline:
      r'Harbor has the larger total stock-market value. The $10 order puts $9 into shares. The practice holdings are 80% Aster.',
  correctChoiceId: 'include-value-fees-and-risk',
  choices: [
    ActivityChoice(
      id: 'include-value-fees-and-risk',
      label: 'Keep all three checks',
      detail:
          r'Harbor’s total is $2,000. The order buys $9 in shares. The separate holdings are 80% Aster. These facts do not pick a winner.',
    ),
    ActivityChoice(
      id: 'choose-cheapest-share',
      label: 'Choose the cheapest share',
      detail:
          'Harbor’s lower share price proves it is the better investment; the other checks can wait.',
    ),
    ActivityChoice(
      id: 'ignore-the-fee',
      label: 'Leave out the fee',
      detail:
          r'Harbor’s total is $2,000 and the holdings are 80% Aster. The order puts the full $10 into shares.',
    ),
  ],
  challengeTitle: 'Give each source its own conclusion.',
  challengeText:
      r'Harbor’s total stock-market value is $5 × 400 = $2,000. In the order example, the fee leaves $9 for shares. In the holdings example, $80 of $100 depends on Aster. None of these facts predicts a winner.',
  correctedFeedback:
      'You revised the comparison and kept each conclusion within its evidence. Both your first answer and the corrected note are saved.',
  successFeedback:
      'You checked the whole company, followed the fee and grouped the holdings. Your comparison gives the team facts without promising an outcome.',
  journalEvidence:
      r'The separate examples establish three facts: Harbor’s total stock-market value is $2,000 versus Aster’s $1,000; the $10 order buys $9 in shares after its $1 fee; and 80% of the $100 practice holdings is in Aster. The sources do not establish future returns or which investment is better.',
  evidence: [companyValueEvidence, feeEvidence, concentrationEvidence],
  presentationOrder: [
    'ignore-the-fee',
    'include-value-fees-and-risk',
    'choose-cheapest-share',
  ],
);

const teamSalesEvidence = ActivityEvidence(
  'Nia’s sales note',
  [
    ('Previous quarter sales', r'$1,000'),
    ('Current quarter sales', r'$1,500'),
    ('Current quarter costs', 'Not included'),
  ],
  'Sales rose by 50%. Without current costs, this note cannot establish '
      'whether profit rose or fell.',
);

const returnedCostEvidence = ActivityEvidence(
  'Figures returned by Nia',
  [
    ('Previous quarter sales', r'$1,000'),
    ('Previous quarter costs', r'$600'),
    ('Previous quarter profit', r'$400'),
    ('Current quarter sales', r'$1,500'),
    ('Current quarter costs', r'$1,300'),
    ('Current quarter profit', r'$200'),
  ],
  'In this fictional example, profit is sales minus the costs shown. Sales '
      'rose, while profit fell from \$400 to \$200.',
);

const reviewTeamUpdateActivity = ActivityDefinition._(
  id: 'review-team-update',
  title: 'Review the team’s update',
  officeDescription:
      'Nia has a sales update with one important figure missing.',
  intro:
      'Nia from the research team has brought a new Aster sales note. Decide '
      'what the team can responsibly do while its costs are missing.',
  sourceIntro:
      'The sales comparison is complete. The current cost figure is not in '
      'the note, so profit cannot be compared yet.',
  sourceTitle: 'Team sales update',
  sourceExplanation:
      'This is a fictional internal update. Both choices keep the missing '
      'costs explicit and avoid an unsupported profit claim.',
  draftHeadline: 'Sales rose by 50%. What should the team do next?',
  correctedHeadline:
      'State only the sales result, or wait for costs before comparing profit.',
  correctChoiceId: 'share-qualified-sales',
  acceptedChoiceIds: ['share-qualified-sales', 'request-missing-costs'],
  choices: [
    ActivityChoice(
      id: 'share-qualified-sales',
      label: 'Share a qualified update',
      detail:
          'Sales rose 50%. Costs are missing, so this update makes no claim '
          'about profit.',
    ),
    ActivityChoice(
      id: 'request-missing-costs',
      label: 'Request the missing costs',
      detail:
          'Ask Nia for the current costs before the team makes any comparison '
          'about profit.',
    ),
  ],
  challengeTitle: 'Keep the limit visible.',
  challengeText:
      'A sales-only update must say that costs are missing. A profit comparison '
      'must wait for those costs. Either responsible action can move the work '
      'forward.',
  correctedFeedback:
      'You kept the missing costs visible before committing the team’s next '
      'step.',
  successFeedback:
      'Your decision is saved. Nia can now respond to the exact action you '
      'chose.',
  journalEvidence:
      'Current sales were \$1,500 versus \$1,000 previously, a 50% increase. '
      'Current costs were absent, so the note did not support a profit claim.',
  evidence: [teamSalesEvidence],
  branchVariants: {
    'share-qualified-sales': ActivityBranchVariant(
      intro:
          'Nia brought a sales note with no current cost figure. You can share '
          'the sales result only if its limit stays attached.',
      draftHeadline: 'Sales rose by 50%. Costs are not included.',
      correctedHeadline:
          'Sales rose by 50%. Costs are missing, so this says nothing yet '
          'about profit.',
      correctedFeedback:
          'You revised the draft so its sales result and its limit stay '
          'together.',
      successFeedback:
          'Your qualified sales-only update is saved for Nia. It does not '
          'imply that profit rose.',
      journalEvidence:
          'You chose to share a qualified sales-only update: sales rose from '
          '\$1,000 to \$1,500, while current costs and profit remained unknown.',
      outcomeTitle: 'Qualified update saved.',
      officeConsequence:
          'Nia: I have your qualified sales-only update. I’ll bring the costs '
          'back so we can revisit it.',
    ),
    'request-missing-costs': ActivityBranchVariant(
      intro:
          'Nia brought a sales note with no current cost figure. You can hold '
          'the profit comparison and ask her to complete the source.',
      draftHeadline: 'Cost figures requested before comparing profit.',
      correctedHeadline:
          'The profit comparison is waiting for the missing current costs.',
      correctedFeedback:
          'You kept the request tied to the exact figure the comparison needs.',
      successFeedback:
          'Your request for the missing costs is saved. No profit claim has '
          'been made.',
      journalEvidence:
          'You asked Nia for current costs before comparing profit. Sales rose '
          'from \$1,000 to \$1,500, but profit remained unknown.',
      outcomeTitle: 'Request sent.',
      officeConsequence:
          'Nia: I have your request for the missing costs. I’ll return with '
          'the figures before we compare profit.',
    ),
  },
);

const readReturnedCostsActivity = ActivityDefinition._(
  id: 'read-returned-costs',
  title: 'Read the returned costs',
  officeDescription: 'Nia has returned with the missing fictional figures.',
  intro:
      'Nia is back with the cost figures. Read them before returning to the '
      'action you saved.',
  sourceIntro:
      'Put sales and costs together for each quarter. The same sales increase '
      'can now be read alongside profit.',
  sourceTitle: 'Completed team figures',
  sourceExplanation:
      'These figures arrive in an authored later scene. They are stored app '
      'content, not live company data.',
  draftHeadline: 'Sales rose by 50%, so what happened to profit?',
  correctedHeadline:
      'Sales rose by 50%, while profit fell from \$400 to \$200.',
  correctChoiceId: 'compare-sales-and-costs',
  choices: [
    ActivityChoice(
      id: 'compare-sales-and-costs',
      label: 'Compare sales and costs',
      detail:
          'Costs rose from \$600 to \$1,300. Profit fell from \$400 to \$200.',
    ),
    ActivityChoice(
      id: 'repeat-sales-only',
      label: 'Repeat the sales result',
      detail: 'Sales rose 50%, so profit must have risen too.',
    ),
  ],
  challengeTitle: 'The returned costs change what can be concluded.',
  challengeText:
      'Current costs were \$1,300. Subtracting them from \$1,500 sales leaves '
      '\$200 profit, down from the previous \$400.',
  correctedFeedback:
      'You used the returned costs. The comparison now separates sales growth '
      'from profit decline.',
  successFeedback:
      'You checked Nia’s returned figures. The team can now revisit the earlier '
      'action with a supported profit comparison.',
  journalEvidence:
      'Previous profit was \$1,000 − \$600 = \$400. Current profit was '
      '\$1,500 − \$1,300 = \$200. Sales rose by 50%, while profit fell by 50%.',
  evidence: [returnedCostEvidence],
  presentationOrder: ['repeat-sales-only', 'compare-sales-and-costs'],
);

const finishTeamUpdateActivity = ActivityDefinition._(
  id: 'finish-team-update',
  title: 'Finish the team’s update',
  officeDescription:
      'Return to your saved decision and apply Nia’s completed figures.',
  intro:
      'The missing figures are here. Finish the exact path you committed to '
      'earlier, then bring the work back to Ada and Nia.',
  sourceIntro:
      'Your first decision remains filed. The returned figures now support a '
      'profit comparison on either path.',
  sourceTitle: 'Saved action and returned figures',
  sourceExplanation:
      'The first decision is never replaced by a replay. This follow-up applies '
      'the new figures to that saved path.',
  draftHeadline: 'How should the saved team action be completed?',
  correctedHeadline:
      'Apply the returned costs and state that profit fell despite higher sales.',
  correctChoiceId: 'apply-returned-figures',
  choices: [
    ActivityChoice(
      id: 'apply-returned-figures',
      label: 'Apply the returned figures',
      detail:
          'Use the \$1,300 costs to show that current profit was \$200, down '
          'from \$400.',
    ),
    ActivityChoice(
      id: 'leave-earlier-action',
      label: 'Leave the earlier action unchanged',
      detail:
          'Keep the sales-only draft or open request unchanged even though the '
          'missing costs have arrived.',
    ),
  ],
  challengeTitle: 'New evidence deserves a return to the earlier work.',
  challengeText:
      'The saved decision records what was responsible when costs were missing. '
      'Now that \$1,300 in costs has arrived, the team can finish the profit '
      'comparison without rewriting that history.',
  correctedFeedback:
      'You returned to the saved action and applied the new figures. Its '
      'original branch remains in the Journal.',
  successFeedback:
      'You applied the returned figures while preserving the team’s earlier '
      'decision.',
  journalEvidence:
      'The saved team action was revisited after costs arrived. Current profit '
      'was \$200 versus \$400 previously; the original action remains recorded.',
  evidence: [returnedCostEvidence],
  branchVariants: {
    'share-qualified-sales': ActivityBranchVariant(
      intro:
          'You shared a qualified sales-only update. Nia has returned with the '
          'costs; revise that draft without erasing what it said earlier.',
      draftHeadline: 'Sales rose by 50%. Costs were still pending.',
      correctedHeadline:
          'Sales rose by 50%, while profit fell from \$400 to \$200.',
      correctedFeedback:
          'You revised the qualified draft when the costs arrived. Its original '
          'limit remains filed.',
      successFeedback:
          'You completed the qualified sales update with Nia’s costs. The '
          'earlier sales-only version remains in your Journal.',
      journalEvidence:
          'After sharing a qualified sales-only update, you returned when costs '
          'arrived and added that profit fell from \$400 to \$200.',
      outcomeTitle: 'Qualified update revised.',
      officeConsequence:
          'Ada: You kept the original limit and returned when Nia brought the '
          'costs. Nia: The completed update is ready for the team.',
    ),
    'request-missing-costs': ActivityBranchVariant(
      intro:
          'You requested the missing costs before comparing profit. Nia has '
          'returned; complete the comparison your request held open.',
      draftHeadline: 'Profit comparison held until costs arrived.',
      correctedHeadline:
          'The returned costs show profit fell from \$400 to \$200.',
      correctedFeedback:
          'You completed the comparison after the requested costs arrived. The '
          'original request remains filed.',
      successFeedback:
          'You completed the held comparison with Nia’s costs. The earlier '
          'request remains in your Journal.',
      journalEvidence:
          'After requesting the missing costs, you completed the held profit '
          'comparison: profit fell from \$400 to \$200.',
      outcomeTitle: 'Requested comparison completed.',
      officeConsequence:
          'Ada: You waited for the evidence and then finished the comparison. '
          'Nia: The completed update is ready for the team.',
    ),
  },
);

const lossLimitEvidence = ActivityEvidence(
  'Fictional monthly budget · US dollars',
  [
    ('Money this month', r'$200'),
    ('Rent', r'$120'),
    ('Food', r'$50'),
    ('Savings', r'$10'),
    ('Spare to invest', r'$20'),
  ],
  'Rent, food and savings are already committed. Only the spare amount could '
      'be lost without changing the month. These figures are invented for practice, '
      'not advice about your own money.',
);

const planPromiseEvidence = ActivityEvidence(
  'A plan you can keep, and a promise you cannot',
  [
    ('Amount to invest', r'$20 spare'),
    ('When to review', 'In three months'),
    ('Sell if it drops to', r'$10'),
    ('Promised return', 'Cannot be guaranteed'),
  ],
  'The first three are choices you control. A return is set by the market, so '
      'it cannot be promised. These figures are invented for practice.',
);

const planFileEvidence = ActivityEvidence(
  'The plan to file',
  [
    ('Amount at risk', r'$20 spare, not $200'),
    ('When to review', 'In three months'),
    ('Sell if it reaches', r'$10'),
    ('Promised return', 'None'),
  ],
  'This plan keeps the loss limit from the budget and the honesty from the '
      'earlier step. These figures are invented for practice.',
);

const setALossLimitActivity = ActivityDefinition._(
  id: 'set-a-loss-limit',
  title: 'Set a loss limit',
  officeDescription:
      'Decide how much of a budget you could invest and still be fine.',
  intro:
      'The draft plan puts a whole month’s money into one stock. Check what '
      'that money is already needed for.',
  sourceIntro:
      'Only the spare amount is money you could lose without changing your month.',
  sourceTitle: 'A fictional monthly budget',
  sourceExplanation:
      'Rent, food and savings are already spoken for. The spare amount is what '
      'is left after them. These are invented figures for practice.',
  draftHeadline: r'Put the whole $200 into one stock this month.',
  correctedHeadline:
      r'Invest only the $20 spare and leave rent, food and savings alone.',
  correctChoiceId: 'commit-spare-only',
  choices: [
    ActivityChoice(
      id: 'commit-spare-only',
      label: 'Invest the spare only',
      detail:
          r'Keep rent, food and savings. Invest the $20 you could lose without harm.',
    ),
    ActivityChoice(
      id: 'commit-everything',
      label: 'Invest everything',
      detail: r'Put all $200 in, and find another way to cover rent and food.',
    ),
  ],
  challengeTitle: 'Only spare money can go at risk.',
  challengeText:
      r'Rent, food and savings take $180 of the $200, leaving $20 spare. A '
      r'stock can fall to nothing, so only money you could lose without harm '
      'should go in. This is a fictional exercise, not advice about your own money.',
  correctedFeedback:
      r'You kept the committed money safe and set the $20 spare as the limit. '
      'The plan now risks only what could be lost.',
  successFeedback:
      r'You invested only the $20 spare. Rent, food and savings stay untouched, '
      'whatever the stock does.',
  journalEvidence:
      r'In this fictional budget, $200 for the month covered $120 rent, $50 '
      r'food and $10 savings, leaving $20 spare. Only that $20 was set as money '
      'that could be lost. Prices can fall, and this exercise is not advice '
      'about real money.',
  evidence: [lossLimitEvidence],
  presentationOrder: ['commit-everything', 'commit-spare-only'],
);

const planNotAPromiseActivity = ActivityDefinition._(
  id: 'plan-not-a-promise',
  title: 'A plan is not a promise',
  officeDescription:
      'Tell a plan you can keep from a return no one can promise.',
  intro:
      'The draft promises what the money will become. Check what a plan can '
      'actually control.',
  sourceIntro:
      'A plan lists actions and limits you choose. It cannot set the price.',
  sourceTitle: 'A plan you can keep, and a promise you cannot',
  sourceExplanation:
      'You control how much to invest, when to review and when to sell. You do '
      'not control the price, so the return cannot be promised. These figures '
      'are invented for practice.',
  draftHeadline: r'This plan will turn the $20 into $30.',
  correctedHeadline:
      r'Invest the $20 spare, review in three months, and accept that the '
      'return is not guaranteed.',
  correctChoiceId: 'state-actions-and-limits',
  choices: [
    ActivityChoice(
      id: 'state-actions-and-limits',
      label: 'State actions and a limit',
      detail:
          r'Invest the $20 spare, review in three months, and sell if it drops '
          r'to $10. Returns are not guaranteed.',
    ),
    ActivityChoice(
      id: 'promise-a-return',
      label: 'Promise a return',
      detail: r'The plan will grow the $20 into $30 within three months.',
    ),
  ],
  challengeTitle: 'A plan sets actions, not outcomes.',
  challengeText:
      r'You can decide how much to invest, when to review and when to sell. You '
      r'cannot decide the price, so no honest plan promises $30. These are '
      'fictional figures for practice.',
  correctedFeedback:
      'You rewrote the plan as actions and a limit. It no longer promises a '
      'return you cannot control.',
  successFeedback:
      'You kept the plan to what you can decide. A plan guides your actions; it '
      'cannot guarantee the result.',
  journalEvidence:
      r'The draft promised the $20 would become $30. The corrected plan set '
      r'actions and a limit instead: invest the spare, review in three months, '
      r'sell at $10, with no guaranteed return. These are fictional figures for '
      'practice.',
  evidence: [planPromiseEvidence],
  presentationOrder: ['promise-a-return', 'state-actions-and-limits'],
);

const writeThePlanActivity = ActivityDefinition._(
  id: 'write-the-plan',
  title: 'Write the plan',
  officeDescription:
      'Bring the limit and the honest framing into one short plan.',
  intro:
      'You set a loss limit and separated a plan from a promise. Choose the '
      'written plan that keeps both.',
  sourceIntro:
      'A plan to file keeps the spare-only limit and makes no promise about the '
      'return.',
  sourceTitle: 'Three draft plans',
  sourceExplanation:
      'Each plan is one you could file. Only one keeps the limit and avoids '
      'promising a result. These are fictional examples.',
  draftHeadline: 'Which plan should we file?',
  correctedHeadline:
      r'Invest the $20 spare, review in three months, sell at $10, and make no '
      'promise about the return.',
  correctChoiceId: 'keep-limit-and-no-promise',
  choices: [
    ActivityChoice(
      id: 'keep-limit-and-no-promise',
      label: 'Keep the limit and the honesty',
      detail:
          r'Invest only the $20 spare, review in three months, sell if it '
          r'reaches $10, and state that returns are not guaranteed.',
    ),
    ActivityChoice(
      id: 'drop-the-limit',
      label: 'Drop the limit',
      detail:
          r'Invest the full $200 this month, review in three months, and state '
          'that returns are not guaranteed.',
    ),
    ActivityChoice(
      id: 'promise-the-gain',
      label: 'Promise the gain',
      detail: r'Invest the $20 spare and file that it will grow into $30.',
    ),
  ],
  challengeTitle: 'Keep both the limit and the honesty.',
  challengeText:
      r'One plan risks the whole $200 instead of the $20 spare. Another promises '
      r'a $30 result no one can guarantee. The plan to file invests only the '
      'spare and makes no promise. These are fictional figures for practice.',
  correctedFeedback:
      'You filed the plan that keeps the loss limit and avoids a promised '
      'return. Both earlier lessons are in it.',
  successFeedback:
      r'Your written plan risks only the $20 spare and promises nothing about '
      'the return. That is a plan you can keep.',
  journalEvidence:
      r'The filed plan invested only the $20 spare, set a three-month review and '
      r'a $10 sell point, and made no promise about the return. The rejected '
      r'plans either risked the full $200 or promised a $30 result. These are '
      'fictional figures for practice.',
  evidence: [planFileEvidence],
  presentationOrder: [
    'drop-the-limit',
    'keep-limit-and-no-promise',
    'promise-the-gain',
  ],
);

final studyActivities = List<ActivityDefinition>.unmodifiable([
  checkTheDateActivity,
  salesAndProfitActivity,
  checkTheSampleActivity,
  prepareTheUpdateActivity,
  compareCompanyValueActivity,
  countTheFeesActivity,
  checkConcentrationActivity,
  prepareTheComparisonActivity,
  reviewTeamUpdateActivity,
  readReturnedCostsActivity,
  finishTeamUpdateActivity,
  setALossLimitActivity,
  planNotAPromiseActivity,
  writeThePlanActivity,
]);

ActivityDefinition? studyActivityById(String id) {
  for (final activity in studyActivities) {
    if (activity.id == id) return activity;
  }
  return null;
}
