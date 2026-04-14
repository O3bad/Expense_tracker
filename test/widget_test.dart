import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spendly/theme/app_theme.dart';

void main() {
  test('AppTheme defines primary brand color', () {
    expect(AppTheme.primary, const Color(0xFF6C63FF));
  });
}
