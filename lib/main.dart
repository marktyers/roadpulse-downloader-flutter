import 'package:flutter/material.dart';

import 'src/ui/downloader_page.dart';

void main() => runApp(const RoadPulseApp());

final class RoadPulseApp extends StatelessWidget {
  const RoadPulseApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'RoadPulse Downloader',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff195ca8)),
          useMaterial3: true,
        ),
        home: const DownloaderPage(),
      );
}
