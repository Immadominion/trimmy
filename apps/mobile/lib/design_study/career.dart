import 'practice_catalog.generated.dart';
import 'progress.dart';

/// Career position is derived from acknowledged practice history. No points,
/// purchases, account status or wall-clock date can unlock a floor.
class OfficeCareer {
  const OfficeCareer(this.progress);
  final OfficeProgress progress;

  bool get isComplete =>
      practiceCatalogActivityIds.every(progress.completions.containsKey);

  String get nextActivityId =>
      progress.active?.activityId ??
      practiceCatalogActivityIds.firstWhere(
        (id) => !progress.completions.containsKey(id),
        orElse: () => practiceCatalogActivityIds.last,
      );

  int get currentFloor => practiceCatalogById[nextActivityId]!.floor;

  List<String> activitiesOn(int floor) => List.unmodifiable(
    practiceCatalogActivityIds.where(
      (id) => practiceCatalogById[id]!.floor == floor,
    ),
  );

  int completedOn(int floor) =>
      activitiesOn(floor).where(progress.completions.containsKey).length;

  bool isFloorUnlocked(int floor) {
    final ids = activitiesOn(floor);
    return ids.isNotEmpty && progress.isUnlocked(ids.first);
  }

  bool canOpen(String id) =>
      progress.isUnlocked(id) &&
      (progress.active == null ||
          progress.active!.stage == 4 ||
          progress.active!.activityId == id);
}
