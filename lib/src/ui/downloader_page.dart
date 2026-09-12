import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_selector/file_selector.dart' as selector;
import 'package:flutter/material.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../download_controller.dart';
import '../app_configuration.dart';
import '../transport/logger_transport.dart';

enum DeliveryMethod { email, localSave }

final class DownloaderPage extends StatefulWidget {
  const DownloaderPage({super.key, this.controller});
  final DownloadController? controller;
  @override
  State<DownloaderPage> createState() => _DownloaderPageState();
}

final class _DownloaderPageState extends State<DownloaderPage> {
  late final DownloadController controller;
  late final bool _ownsController;
  DeliveryMethod delivery = DeliveryMethod.email;
  bool delivering = false;
  Object? _announcedPayload;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    controller = widget.controller ?? DownloadController();
    controller.addListener(_handleControllerChange);
    controller.start();
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChange);
    if (_ownsController) controller.dispose();
    super.dispose();
  }

  void _handleControllerChange() {
    final payload = controller.payload;
    if (controller.phase == DownloadPhase.ready &&
        payload != null &&
        !identical(payload, _announcedPayload)) {
      _announcedPayload = payload;
      unawaited(_beepAndPrompt());
    }
  }

  Future<void> _beepAndPrompt() async {
    unawaited(_playCompletionSound());
    if (!mounted) return;
    final sendNow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline),
        title: const Text('Download complete'),
        content: const Text('The RPB file is ready. Send the email now?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.send),
            label: const Text('Send email'),
          ),
        ],
      ),
    );
    if (sendNow == true) await _deliver();
  }

  Future<void> _playCompletionSound() async {
    final player = AudioPlayer();
    try {
      await player.play(AssetSource('beep.wav'));
      unawaited(player.onPlayerComplete.first
          .timeout(const Duration(seconds: 5))
          .catchError((_) {})
          .whenComplete(player.dispose));
    } catch (_) {
      // A missing audio device must not prevent delivery of a valid download.
      await player.dispose();
    }
  }

  String get _suggestedName {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp = '${now.year}-${two(now.month)}-${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return '${controller.info?.deviceId ?? 'RP-UNKNOWN'}-$stamp.rpb';
  }

  Future<void> _deliver() async {
    final bytes = controller.payload;
    if (bytes == null || delivering) return;
    setState(() => delivering = true);
    try {
      if (!Platform.isAndroid && delivery == DeliveryMethod.localSave) {
        final location = await selector.getSaveLocation(
          suggestedName: _suggestedName,
          acceptedTypeGroups: const [
            selector.XTypeGroup(label: 'RoadPulse binary', extensions: ['rpb'])
          ],
        );
        if (location != null) {
          await XFile.fromData(bytes,
                  mimeType: 'application/octet-stream', name: _suggestedName)
              .saveTo(location.path);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content:
                    Text('Saved ${controller.info!.recordCount} records.')));
          }
        }
      } else {
        if (AppConfiguration.emailRecipient.isEmpty) {
          throw StateError(
              'The delivery email is not configured in this build.');
        }
        final temporary = await getTemporaryDirectory();
        final file = File('${temporary.path}/$_suggestedName');
        await file.writeAsBytes(bytes, flush: true);
        if (Platform.isAndroid || Platform.isMacOS) {
          await FlutterEmailSender.send(Email(
            recipients: const [AppConfiguration.emailRecipient],
            subject: controller.info!.deviceId,
            body:
                'RoadPulse Logger export (${controller.info!.recordCount} records).',
            attachmentPaths: [file.path],
          ));
        } else {
          await SharePlus.instance.share(ShareParams(
            files: [
              XFile(file.path,
                  mimeType: 'application/octet-stream', name: _suggestedName)
            ],
            subject: controller.info!.deviceId,
            text: 'Send this RoadPulse Logger export to '
                '${AppConfiguration.emailRecipient}.',
          ));
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not deliver the file: $error')));
      }
    } finally {
      if (mounted) setState(() => delivering = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('RoadPulse Downloader')),
          body: Center(
              child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_icon,
                        size: 64, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 20),
                    Text(controller.status,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 10),
                    Text(controller.detail,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge),
                    if (Platform.isIOS) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'iPhone and iPad cannot access the logger’s current USB CDC export. '
                        'The logger needs BLE, network, or Apple External Accessory support.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (controller.phase == DownloadPhase.downloading) ...[
                      const SizedBox(height: 24),
                      LinearProgressIndicator(value: controller.progress),
                    ],
                    if (_showPicker) ...[
                      const SizedBox(height: 24),
                      DropdownButtonFormField<LoggerDevice>(
                        initialValue: controller.selectedDevice,
                        decoration: const InputDecoration(
                            labelText: 'Serial device',
                            border: OutlineInputBorder()),
                        items: controller.devices
                            .map((device) => DropdownMenuItem(
                                value: device,
                                child: Text(device.label,
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: controller.selectDevice,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: controller.selectedDevice == null
                              ? null
                              : controller.connect,
                          child: const Text('Connect')),
                    ],
                    if (!Platform.isAndroid &&
                        controller.phase == DownloadPhase.ready) ...[
                      const SizedBox(height: 22),
                      SegmentedButton<DeliveryMethod>(
                        segments: const [
                          ButtonSegment(
                              value: DeliveryMethod.email,
                              icon: Icon(Icons.email_outlined),
                              label: Text('Email')),
                          ButtonSegment(
                              value: DeliveryMethod.localSave,
                              icon: Icon(Icons.save_alt),
                              label: Text('Save locally')),
                        ],
                        selected: {delivery},
                        onSelectionChanged: (value) =>
                            setState(() => delivery = value.single),
                      ),
                    ],
                    if (controller.phase == DownloadPhase.ready) ...[
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: delivering ? null : _deliver,
                        icon: Icon(delivery == DeliveryMethod.email ||
                                Platform.isAndroid
                            ? Icons.attach_email
                            : Icons.save_alt),
                        label: Text(delivering
                            ? 'Preparing…'
                            : (delivery == DeliveryMethod.email ||
                                    Platform.isAndroid
                                ? 'Create email'
                                : 'Save RPB')),
                      ),
                    ],
                    if (controller.phase == DownloadPhase.failed) ...[
                      const SizedBox(height: 16),
                      OutlinedButton(
                          onPressed: controller.reset,
                          child: const Text('Try again')),
                    ],
                    const SizedBox(height: 16),
                    Text('Read-only download · logger flash is never changed',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                )),
          )),
        ),
      );

  bool get _showPicker =>
      controller.devices.length > 1 &&
      (controller.phase == DownloadPhase.waiting ||
          controller.phase == DownloadPhase.failed);
  IconData get _icon => switch (controller.phase) {
        DownloadPhase.ready => Icons.check_circle_outline,
        DownloadPhase.failed => Icons.error_outline,
        DownloadPhase.downloading => Icons.downloading,
        _ => Icons.usb,
      };
}
