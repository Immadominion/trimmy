// Visual review exporter, not an assertion of artwork quality.
// flutter test tool/render_ada_rig_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/design_study/ada_rig.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('export actual runtime rig for visual inspection', () async {
    final bytes = await rootBundle.load('assets/images/ada-acting-v1.webp');
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final frame = await codec.getNextFrame();
    codec.dispose();
    final output = Directory('../../art/studies/runtime/rig-v2')
      ..createSync(recursive: true);
    final samples = <(String, AdaBeat, AdaRigPose)>[
      ('01-listening', AdaBeat.listening, const AdaRigPose()),
      ('02-blink', AdaBeat.listening, const AdaRigPose(eyeOpen: 0)),
      ('03-reading', AdaBeat.reading, AdaRigPose.forBeat(AdaBeat.reading)),
      ('04-thinking', AdaBeat.thinking, AdaRigPose.forBeat(AdaBeat.thinking)),
      (
        '05-correction',
        AdaBeat.correction,
        AdaRigPose.forBeat(AdaBeat.correction),
      ),
      (
        '06-correction-extreme',
        AdaBeat.correction,
        const AdaRigPose(
          headRotation: -.05,
          eyeOpen: .45,
          gestureRotation: -.1,
        ),
      ),
      (
        '07-nod',
        AdaBeat.complete,
        AdaRigPose.reaction(const AdaRigPose(), AdaBeat.complete, .30),
      ),
      ('08-complete', AdaBeat.complete, AdaRigPose.forBeat(AdaBeat.complete)),
    ];
    for (final sample in samples) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(const Color(0xFFFAF9F6), BlendMode.src);
      canvas.scale(2);
      AdaRigPainter(
        image: frame.image,
        pose: sample.$3,
        beat: sample.$2,
      ).paint(canvas, const Size(480, 512));
      final picture = recorder.endRecording();
      final image = await picture.toImage(960, 1024);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File(
        '${output.path}/${sample.$1}.png',
      ).writeAsBytesSync(png!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
    }
    frame.image.dispose();
  });
}
