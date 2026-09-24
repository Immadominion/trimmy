import 'package:flutter/material.dart';
import '../../design/components.dart';
import '../../design/theme.dart';
import '../practice/practice_controller.dart';

Future<void> openBrief(
  BuildContext context,
  PracticeController controller,
) async {
  controller.cue('paper_open.wav');
  await showTrimmySheet(context, BriefSheet(controller: controller));
}

class MentorSheet extends StatelessWidget {
  const MentorSheet({super.key, required this.controller});
  final PracticeController controller;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetHeading('Meet Ada.'),
        const SizedBox(height: 20),
        Center(
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: squircle(28)),
            child: const AdaPortrait(size: 210, decorative: false),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          '“A hunch is a start.\nA good question is better.”',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 20),
        const Text(
          'I’m Ada. Around here, we make room for the thinking behind a decision. You don’t have to know all the answers to take a seat.',
        ),
        const SizedBox(height: 16),
        const Text(
          'We’ll start with a fictional company and one small decision. Nothing in this practice office moves real money.',
          style: TextStyle(color: TrimmyColors.muted),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () async {
              await controller.meetOffice();
              if (context.mounted) {
                Navigator.pop(context);
                openBrief(context, controller);
              }
            },
            child: const Text('Let’s get started'),
          ),
        ),
      ],
    ),
  );
}

const briefChoices = [
  'What does the business actually do?',
  'What would changing the position cost?',
  'How much uncertainty can I live with?',
];
const briefResponses = [
  'A rising price doesn’t explain a business. Start with how it earns money, who buys from it, and what could change.',
  'Fees and spread matter, especially for a small position. A quoted price is only one part of the cost.',
  'A position can lose value. Knowing your own limits is useful before looking at someone else’s confidence.',
];

class BriefSheet extends StatefulWidget {
  const BriefSheet({super.key, required this.controller});
  final PracticeController controller;
  @override
  State<BriefSheet> createState() => _BriefSheetState();
}

class _BriefSheetState extends State<BriefSheet> {
  late int? choice = widget.controller.selectedChoice;
  late final note = TextEditingController(text: widget.controller.journalNote);
  bool saving = false;
  String? error;
  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (choice == null || note.text.trim().isEmpty) {
      setState(
        () => error = 'Choose a question and write a short note to save.',
      );
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.saveBrief(
        choice: choice!,
        note: note.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.controller.setTab(2);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'Your note couldn’t be saved. Keep it here and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SheetHeading('The first question'),
        const SizedBox(height: 12),
        const StatusTag('Practice brief 01', color: TrimmyColors.paleGreen),
        const SizedBox(height: 24),
        Text(
          'A friend has a hunch.',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 16),
        const Text(
          'They like Aster Labs, a fictional company. Its price rose this week. Before deciding whether a position belongs at your desk, what would you look into?',
        ),
        const SizedBox(height: 24),
        for (var i = 0; i < briefChoices.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Semantics(
              button: true,
              selected: choice == i,
              child: Material(
                color: choice == i ? TrimmyColors.paleGreen : Colors.white,
                shape: RoundedSuperellipseBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: choice == i ? TrimmyColors.pine : TrimmyColors.line,
                    width: choice == i ? 1.5 : 1,
                  ),
                ),
                child: InkWell(
                  customBorder: squircle(18),
                  onTap: () {
                    setState(() => choice = i);
                    widget.controller.cue('soft_tap.wav');
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        Icon(
                          choice == i
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 20,
                          color: choice == i
                              ? TrimmyColors.pine
                              : TrimmyColors.muted,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            briefChoices[i],
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (choice != null) ...[
          const SizedBox(height: 10),
          SquirclePanel(
            color: const Color(0xFFF0EEEA),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ada’s take',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(briefResponses[choice!]),
                const SizedBox(height: 8),
                const Text(
                  'Each question is useful. There isn’t a stock pick to win here.',
                  style: TextStyle(color: TrimmyColors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        TextField(
          controller: note,
          minLines: 3,
          maxLines: 5,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'A note for your future self',
            hintText: 'What would you want to understand better?',
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error!,
                style: const TextStyle(color: TrimmyColors.loss),
              ),
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: saving ? null : save,
            child: Text(saving ? 'Saving…' : 'Save to my journal'),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Saved on this device. This practice brief does not place a trade.',
          style: TextStyle(fontSize: 12, color: TrimmyColors.muted),
        ),
      ],
    ),
  );
}

class InviteSheet extends StatefulWidget {
  const InviteSheet({super.key, required this.controller});
  final PracticeController controller;
  @override
  State<InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<InviteSheet> {
  final form = GlobalKey<FormState>();
  final handle = TextEditingController();
  final message = TextEditingController(
    text: 'There’s an open seat at my office. Come bring a fresh perspective.',
  );
  bool preview = false;
  bool saving = false;
  String? error;
  @override
  void dispose() {
    handle.dispose();
    message.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.saveDraft(
        handle: handle.text.trim(),
        message: message.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      widget.controller.setTab(2);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error =
              widget.controller.drafts.length >= PracticeController.maxDrafts
              ? 'This practice office holds up to 20 drafts. Your existing drafts have been kept.'
              : 'The draft couldn’t be saved. Check the details and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Form(
      key: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetHeading(
            preview ? 'An offer, in your words.' : 'Save someone a seat.',
          ),
          const SizedBox(height: 16),
          const StatusTag('Practice offer'),
          const SizedBox(height: 22),
          if (!preview) ...[
            const Text(
              'Try writing an invitation to your office. You can review it before saving a local draft.',
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: handle,
              maxLength: 16,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Their X handle',
                hintText: '@yourfriend',
              ),
              validator: (value) =>
                  RegExp(
                    r'^@?[A-Za-z0-9_]{1,15}$',
                  ).hasMatch(value?.trim() ?? '')
                  ? null
                  : 'Use an X handle with 1 to 15 letters, numbers or underscores.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: message,
              minLines: 3,
              maxLines: 5,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Your note'),
              validator: (value) => (value?.trim().isNotEmpty ?? false)
                  ? null
                  : 'Write a short invitation.',
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  if (form.currentState!.validate()) {
                    setState(() => preview = true);
                    widget.controller.cue('paper_open.wav');
                  }
                },
                child: const Text('Preview offer'),
              ),
            ),
          ] else ...[
            SquirclePanel(
              border: true,
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.mark_email_unread_outlined,
                    size: 32,
                    color: TrimmyColors.pine,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Dear ${handle.text.startsWith('@') ? handle.text : '@${handle.text}'},',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message.text.trim(),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'A seat. A fresh start. Good company.',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your Trimmy office',
                    style: TextStyle(color: TrimmyColors.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: saving ? null : save,
                child: Text(saving ? 'Saving…' : 'Save draft'),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: saving
                    ? null
                    : () => setState(() => preview = false),
                child: const Text('Edit offer'),
              ),
            ),
          ],
          if (error != null)
            Text(error!, style: const TextStyle(color: TrimmyColors.loss)),
          const SizedBox(height: 12),
          const Text(
            'This handle is not verified. The draft stays on this device. No message, link, asset or money will be sent.',
            style: TextStyle(fontSize: 12, color: TrimmyColors.muted),
          ),
        ],
      ),
    ),
  );
}

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key, required this.controller});
  final PracticeController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SheetHeading('Make it your space.'),
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Sound effects'),
            subtitle: const Text('Quiet taps and paper. No music.'),
            value: controller.soundEnabled,
            onChanged: controller.setSound,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reduce motion'),
            subtitle: const Text('Keep transitions still and simple.'),
            value: controller.reduceMotion,
            onChanged: controller.setReduceMotion,
          ),
          if (MediaQuery.disableAnimationsOf(context))
            const Text(
              'Your system’s reduced-motion setting is also active.',
              style: TextStyle(color: TrimmyColors.muted),
            ),
          const Divider(height: 36),
          const Text(
            'About this office',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          const Text(
            'Trimmy’s practice office lets you explore the experience with fictional companies. Notes and draft offers are stored only on this device. Live wallets, stock gifts and swaps are not connected.',
            style: TextStyle(color: TrimmyColors.muted),
          ),
          const SizedBox(height: 20),
          TextButton.icon(
            onPressed: () =>
                showLicensePage(context: context, applicationName: 'Trimmy'),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('Open-source licenses'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () async {
              final reset = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear this practice office?'),
                  content: const Text(
                    'This removes your local note, draft offers and progress. Your sound and motion preferences stay.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Keep my progress'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Clear practice'),
                    ),
                  ],
                ),
              );
              if (reset == true) {
                await controller.clearPractice();
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Clear practice progress'),
          ),
        ],
      ),
    ),
  );
}
