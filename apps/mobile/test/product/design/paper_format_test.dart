import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/design/paper_format.dart';

void main() {
  test('paper display groups and rounds exact decimal strings', () {
    expect(formatPaperForDisplay('9999.999999'), '10,000');
    expect(formatPaperForDisplay('99.999870'), '100');
    expect(formatPaperForDisplay('333.937329'), '333.94');
    expect(formatPaperForDisplay('1234.5'), '1,234.5');
    expect(formatPaperForDisplay('0.004999'), '0');
    expect(formatPaperForDisplay('0.005000'), '0.01');
  });

  test('paper display refuses to reinterpret malformed values', () {
    expect(formatPaperForDisplay('-1'), '-1');
    expect(formatPaperForDisplay('01.00'), '01.00');
    expect(formatPaperForDisplay('1.0000000'), '1.0000000');
    expect(formatPaperForDisplay('paper'), 'paper');
  });
}
