import 'activities.dart';
import 'career.dart';
import 'practice_catalog.generated.dart';
import 'progress.dart';

/// A review of acknowledged work, never a new grade, reward or save format.
/// Replays still use the normal activity repository and preserve first choices.
class OfficeCareerReview {
  const OfficeCareerReview(this.progress);
  final OfficeProgress progress;

  bool get available => OfficeCareer(progress).isComplete;
  String? get unfinishedActivityId => progress.active?.activityId;

  List<String> get practiceActivityIds {
    if (!available) return const [];
    final revised = practiceCatalogActivityIds.where(
      (id) => progress.completions[id]!.corrected,
    );
    return List.unmodifiable(
      {
        ...revised,
        OfficeActivityIds.prepareTheComparison,
        OfficeActivityIds.finishTeamUpdate,
        OfficeActivityIds.writeThePlan,
      }.take(3),
    );
  }

  String practiceReason(String id) => progress.completions[id]!.corrected
      ? 'You revised this answer with Ada. Try it again with what you know now.'
      : switch (id) {
          OfficeActivityIds.prepareTheComparison =>
            'Bring company value, fees and risk together again.',
          OfficeActivityIds.finishTeamUpdate =>
            'Follow your team decision through to the returned figures.',
          _ => 'Write a plan that respects your limit.',
        };

  List<CareerReviewFolder> get folders {
    if (!available) return const [];
    return List.unmodifiable([
      _folder(
        1,
        OfficeActivityIds.prepareTheUpdate,
        'Check what a headline leaves out.',
      ),
      _folder(
        2,
        OfficeActivityIds.prepareTheComparison,
        'Price, fees and risk answer different questions.',
      ),
      _folder(
        3,
        OfficeActivityIds.reviewTeamUpdate,
        'A useful team decision can include what you do not know yet.',
        resultId: OfficeActivityIds.finishTeamUpdate,
      ),
      _folder(
        4,
        OfficeActivityIds.writeThePlan,
        'Choose your limits. Keep a plan separate from a promised return.',
      ),
    ]);
  }

  CareerReviewFolder _folder(
    int floor,
    String id,
    String takeaway, {
    String? resultId,
  }) {
    final activity = studyActivityById(id)!;
    final resultActivity = studyActivityById(resultId ?? id)!;
    final saved = progress.completions[id]!;
    final branch = progress
        .completions[OfficeActivityIds.reviewTeamUpdate]!
        .selectedChoiceId;
    final result = resultActivity.branchVariants[branch];
    return CareerReviewFolder(
      floor: floor,
      title: practiceCatalogFloors[floor]!,
      activityId: id,
      activityTitle: activity.title,
      takeaway: takeaway,
      firstDecision: activity.choices
          .firstWhere((choice) => choice.id == saved.selectedChoiceId)
          .detail,
      revised: saved.corrected,
      filedStatement:
          result?.correctedHeadline ?? resultActivity.correctedHeadline,
      evidence: result?.journalEvidence ?? resultActivity.journalEvidence,
      colleagueReply: floor == 3 ? result?.officeConsequence : null,
    );
  }
}

class CareerReviewFolder {
  const CareerReviewFolder({
    required this.floor,
    required this.title,
    required this.activityId,
    required this.activityTitle,
    required this.takeaway,
    required this.firstDecision,
    required this.revised,
    required this.filedStatement,
    required this.evidence,
    this.colleagueReply,
  });
  final int floor;
  final String title,
      activityId,
      activityTitle,
      takeaway,
      firstDecision,
      filedStatement,
      evidence;
  final bool revised;
  final String? colleagueReply;
}
