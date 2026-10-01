import 'package:flutter_test/flutter_test.dart';
import 'package:roadpulse_downloader/src/delivery_content.dart';
import 'package:roadpulse_downloader/src/protocol/rpb_validator.dart';
import 'package:roadpulse_downloader/src/protocol/rpb_profile.dart';

void main() {
  test('email subject contains the logger serial number and tags', () {
    const info = RpbInfo(
      deviceId: 'RP-123ABC',
      recordCount: 10,
      tags: ['fleet-7', 'coventry'],
      profile: RpbProfileRegistry.legacy,
    );
    expect(emailSubjectFor(info), 'RP-123ABC — fleet-7, coventry');
  });

  test('email subject remains the serial number when there are no tags', () {
    const info = RpbInfo(
      deviceId: 'RP-123ABC',
      recordCount: 10,
      tags: [],
      profile: RpbProfileRegistry.legacy,
    );
    expect(emailSubjectFor(info), 'RP-123ABC');
  });
}
