import 'package:flutter/material.dart';

import '../design/product_components.dart';
import '../design/product_theme.dart';
import '../onboarding/onboarding_models.dart';

/// Optional after the first trade. A choice is written to the current profile;
/// closing this page leaves the persona unanswered.
class PersonaPickerPage extends StatefulWidget {
  const PersonaPickerPage({super.key, required this.onChoose});

  final Future<void> Function(TraderPersona persona) onChoose;

  @override
  State<PersonaPickerPage> createState() => _PersonaPickerPageState();
}

class _PersonaPickerPageState extends State<PersonaPickerPage> {
  TraderPersona? _selected;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final selected = _selected;
    if (selected == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onChoose(selected);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save your choice. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: ProductColor.paper,
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    tooltip: 'Close',
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
                const SizedBox(height: 30),
                Text(
                  'Pick your trader',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 9),
                Text(
                  'Who will you play as?',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 29),
                for (final persona in TraderPersona.values) ...[
                  _option(context, persona),
                  const SizedBox(height: 11),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 11),
                  Text(
                    _error!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: ProductColor.loss),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
            child: SizedBox(
              width: double.infinity,
              child: ProductButton(
                key: const ValueKey('persona-choose'),
                label: _saving ? 'Saving…' : 'Choose',
                onPressed: _selected == null || _saving ? null : _save,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _option(BuildContext context, TraderPersona persona) {
    final selected = _selected == persona;
    return Material(
      color: selected ? const Color(0xFFF2EFFF) : ProductColor.paperRaised,
      shape: productSquircle(24).copyWith(
        side: selected
            ? const BorderSide(color: ProductColor.violet, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        key: ValueKey('persona-option-${persona.id}'),
        customBorder: productSquircle(24),
        onTap: _saving ? null : () => setState(() => _selected = persona),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
          child: Row(
            children: [
              SizedBox(
                width: 68,
                height: 68,
                child: Image.asset(
                  'assets/images/ui_review/persona-${persona.id}-avatar-v1.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      persona.label,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      persona.description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
