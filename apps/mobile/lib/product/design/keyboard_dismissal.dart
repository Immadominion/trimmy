import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Closes the keyboard when someone taps anywhere that is not a control.
///
/// Flutter keeps a text field focused after a tap outside it on phones, and
/// iOS number pads have no Done key, so without this the keyboard stays over
/// sheets such as Fast buy until the sheet closes. Sits above the navigator,
/// so it covers every page, sheet and dialog. A tap that a button, field or
/// sheet backdrop claims still goes to it: this handler only wins taps on
/// empty space. Only a focused text field is affected, so keyboard focus on
/// other controls stays where it is.
class KeyboardDismissal extends StatelessWidget {
  const KeyboardDismissal({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    // Touch only: a mouse or trackpad click keeps desktop focus behaviour.
    supportedDevices: const {PointerDeviceKind.touch, PointerDeviceKind.stylus},
    onTap: dismissKeyboard,
    child: child,
  );

  /// Unfocuses the active text field, if there is one.
  static void dismissKeyboard() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null) {
      focus!.unfocus();
    }
  }
}
