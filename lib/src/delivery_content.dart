import 'protocol/rpb_validator.dart';

String emailSubjectFor(RpbInfo info) {
  if (info.tags.isEmpty) return info.deviceId;
  return '${info.deviceId} — ${info.tags.join(', ')}';
}
