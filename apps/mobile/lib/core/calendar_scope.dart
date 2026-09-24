import 'dart:async';
import 'package:flutter/material.dart';

/// Date-based UI refreshes on resume and across midnight without mutating progress.
class CalendarScope extends StatefulWidget {
  const CalendarScope({super.key, required this.readDate, required this.child});
  final DateTime Function() readDate;
  final Widget child;
  static DateTime todayOf(BuildContext context, DateTime fallback) =>
      context.dependOnInheritedWidgetOfExactType<_CalendarDay>()?.date ??
      fallback;
  @override
  State<CalendarScope> createState() => _CalendarScopeState();
}

class _CalendarScopeState extends State<CalendarScope>
    with WidgetsBindingObserver {
  late DateTime date = widget.readDate();
  Timer? timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  void refresh() {
    final next = widget.readDate();
    if (mounted && next != date) setState(() => date = next);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _CalendarDay(date: date, child: widget.child);
}

class _CalendarDay extends InheritedWidget {
  const _CalendarDay({required this.date, required super.child});
  final DateTime date;
  @override
  bool updateShouldNotify(_CalendarDay oldWidget) => oldWidget.date != date;
}
