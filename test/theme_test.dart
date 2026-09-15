import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:roadpulse_downloader/main.dart';

void main() {
  test('provides matching system light and dark themes', () {
    expect(roadPulseLightTheme.brightness, Brightness.light);
    expect(roadPulseDarkTheme.brightness, Brightness.dark);
    expect(roadPulseLightTheme.colorScheme.primary,
        isNot(roadPulseDarkTheme.colorScheme.primary));
  });
}
