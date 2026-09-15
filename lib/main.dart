import 'package:flutter/material.dart';

import 'src/ui/downloader_page.dart';

void main() => runApp(const RoadPulseApp());

const _brandBlue = Color(0xff195ca8);

final roadPulseLightTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: _brandBlue),
  useMaterial3: true,
);

final roadPulseDarkTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: _brandBlue,
    brightness: Brightness.dark,
  ),
  useMaterial3: true,
);

final class RoadPulseApp extends StatelessWidget {
  const RoadPulseApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'RoadPulse Downloader',
        theme: roadPulseLightTheme,
        darkTheme: roadPulseDarkTheme,
        themeMode: ThemeMode.system,
        home: const DownloaderPage(),
      );
}
