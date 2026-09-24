import 'package:flutter_test/flutter_test.dart';
import 'package:trimmy/product/market/order_amount_math.dart';

void main() {
  test('fractional sale presets never round above owned shares', () {
    expect(OrderAmountMath.portion('0.000001', 75), '0');
    expect(OrderAmountMath.portion('0.132042', 25), '0.03301');
    expect(OrderAmountMath.portion('0.132042', 100), '0.132042');
    expect(OrderAmountMath.cents('9950.999999'), '9950.99');
  });
  test('buy estimates floor shares, cash sell estimates cover the target', () {
    expect(OrderAmountMath.sharesForCash('100', '231.42'), '0.432114');
    expect(
      OrderAmountMath.sharesForCash('100', '231.42', selling: true),
      '0.432115',
    );
    expect(OrderAmountMath.cashForShares('0.432115', '231.42'), '100.000053');
  });
}
