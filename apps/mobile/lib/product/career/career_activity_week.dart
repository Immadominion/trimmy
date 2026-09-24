import 'package:flutter/material.dart';
import '../design/product_theme.dart';
import '../market/market_craft.dart';
import 'career_repository.dart';

abstract interface class CareerActivityWeekReader {
  Future<CareerActivityWeek> getActivityWeek();
}

class CareerActivityWeek {
  const CareerActivityWeek({
    required this.serverDate,
    required this.weekStart,
    required this.activeDates,
  });
  final String serverDate, weekStart;
  final Set<String> activeDates;
  factory CareerActivityWeek.fromJson(Object? value) {
    Never invalid() =>
        throw const CareerException(CareerFailure.invalidResponse);
    DateTime parse(Object? v) {
      if (v is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) {
        invalid();
      }
      final date = DateTime.tryParse('${v}T00:00:00Z');
      if (date == null || date.toIso8601String().substring(0, 10) != v) {
        invalid();
      }
      return date;
    }

    if (value is! Map) invalid();
    final today = parse(value['serverDate']);
    final start = parse(value['weekStart']);
    final dates = value['activeDates'];
    if (start.weekday != 1 ||
        today.difference(start).inDays < 0 ||
        today.difference(start).inDays > 6 ||
        dates is! List ||
        dates.length > 7) {
      invalid();
    }
    final active = <String>{};
    for (final date in dates) {
      final parsed = parse(date);
      if (parsed.isBefore(start) ||
          parsed.isAfter(today) ||
          !active.add(date as String)) {
        invalid();
      }
    }
    return CareerActivityWeek(
      serverDate: value['serverDate'] as String,
      weekStart: value['weekStart'] as String,
      activeDates: Set.unmodifiable(active),
    );
  }
}

class CareerStreakStrip extends StatelessWidget {
  const CareerStreakStrip({
    super.key,
    required this.career,
    this.week,
    this.onRetry,
    this.embedded = false,
  });
  final CareerSummary career;
  final CareerActivityWeek? week;
  final VoidCallback? onRetry;
  final bool embedded;
  @override
  Widget build(BuildContext context) {
    final today = DateTime.parse(
      '${week?.serverDate ?? career.serverDate}T00:00:00Z',
    );
    final start = week == null
        ? today.subtract(Duration(days: today.weekday - 1))
        : DateTime.parse('${week!.weekStart}T00:00:00Z');
    return Container(
      key: const ValueKey('career-streak-strip'),
      padding: const EdgeInsets.fromLTRB(17, 16, 17, 18),
      decoration: ShapeDecoration(
        color: const Color(0xFFF1EDF9),
        shape: embedded ? const RoundedRectangleBorder() : productSquircle(26),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/images/ui_review/icons8/career-streak.png',
                color: const Color(0xFFF47B35),
                colorBlendMode: BlendMode.srcIn,
                width: 22,
                height: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${career.streak.days} day streak',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (onRetry != null)
                IconButton(
                  tooltip: 'Retry activity',
                  onPressed: onRetry,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: MarketPalette.violet,
                    size: 20,
                  ),
                ),
            ],
          ),
          if (week != null) ...[
            const SizedBox(height: 16),
            Row(
              children: List.generate(7, (index) {
                final day = start.add(Duration(days: index));
                final iso = day.toIso8601String().substring(0, 10);
                final active = week?.activeDates.contains(iso) ?? false;
                final current = iso == (week?.serverDate ?? career.serverDate);
                return Expanded(
                  child: Semantics(
                    label:
                        '$iso, ${week == null
                            ? 'activity unavailable'
                            : active
                            ? 'active'
                            : day.isAfter(today)
                            ? 'upcoming'
                            : 'no activity'}',
                    child: ExcludeSemantics(
                      child: Column(
                        children: [
                          Text(
                            const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][index],
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: current
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: MarketPalette.muted,
                            ),
                          ),
                          const SizedBox(height: 9),
                          SizedBox.square(
                            dimension: 28,
                            child: active
                                ? const Icon(
                                    Icons.verified_rounded,
                                    key: ValueKey('streak-active-day'),
                                    color: MarketPalette.violet,
                                    size: 28,
                                  )
                                : Center(
                                    child: Container(
                                      width: 19,
                                      height: 19,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: current
                                            ? const Color(0xFFC9BFE6)
                                            : const Color(0xFFE4DDF1),
                                      ),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }
}
