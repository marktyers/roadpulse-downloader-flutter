# Existing RoadPulse Logger protocol and behaviour

This was derived directly from `roadpulse-downloader-macos` (`main.swift`,
`UsbFrameParser.swift`, `RpbDecoder.swift`, and their tests).

## Discovery and connection

The existing application polls `/dev` every 100 ms and selects the
lexicographically first entry beginning `cu.usbmodem`. It opens that USB CDC
serial device with POSIX `open`, configures raw mode at 115200 baud, and reads in
non-blocking 4096-byte chunks. It does not discover a logger over Wi-Fi,
Bluetooth, Bonjour, mDNS, or any other network mechanism.

There is no request/response handshake. Firmware automatically emits its retained
snapshot when connected, which is why the original instructions say to launch
the application before connecting the logger. The app opens the port and only
reads; it never writes a byte or issues a delete/acknowledgement command.

On macOS this replacement prefers ports containing `usbmodem`. On Windows it
uses serial-port metadata such as RoadPulse/CDC and otherwise auto-selects only
when exactly one serial port exists. A chooser prevents connecting blindly when
the machine has multiple candidates. Android enumerates USB devices, asks the
system for access, and reads through the device's USB serial driver.

## Transport frame

Arbitrary noise may precede this line:

```text
RPB_HEX_BEGIN <decimal-payload-byte-count>\n
```

It is followed by exactly twice that many hexadecimal digits. ASCII space, tab,
CR, and LF are ignored within the payload. Both upper- and lower-case hex are
accepted. Once the declared number of binary bytes has been decoded, the parser
requires this marker within the next 256 received bytes:

```text
\nRPB_HEX_END
```

The parser retains at most 8192 pre-header bytes. It reports progress as decoded
binary bytes divided by the declared payload length. A transfer has no total
duration limit, but fails after 30 seconds with no bytes received.

## RPB profile detection and validation before delivery

The downloader parses the common header before it accesses any records. It
uses the firmware's `record_schema_version` field at offset 8 as the profile
identifier and resolves that identifier through one central registry. It does
not guess a profile from the total file size. All integers are little-endian.

Supported profiles are:

| Profile identifier | Schema version | Record size | Name | Base header | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | 1 | 41 bytes | Legacy | 64 bytes | Supported |
| 2 | 2 | 63 bytes | Full diagnostic (`FULL-63`) | 96 bytes | Supported |

`FULL-63` also contains the firmware's extended-header
`extension_profile` value 3 at offset 50. Legacy headers predate that field;
the same byte belongs to their zero-filled reserved area. This is why the
registry uses `record_schema_version` as the common profile key and separately
checks extension profile 3 for `FULL-63`.

Profile definitions own their record size, base-header size, supported status,
display name, and record decoder. USB framing, file preservation, saving, and
emailing do not contain profile-specific branches. A future format is added by
registering its profile and decoder.

The binary payload must satisfy:

- At least the 12-byte common header must be present before profile detection.
- Header magic at offset 0 is `0x48425052` (`RPBH` on disk).
- Legacy uses binary format version 1, or version 2 when followed by a
  CRC-protected `TAGS` extension. `FULL-63` uses version 2, or version 3 with
  `TAGS`. Header size at offset 6 identifies the manifest offset.
- Record schema and declared record size must match a supported registry entry.
- Byte 47 is 1 (the supported stored-record layout marker).
- CRC-32/ISO-HDLC covers the base header excluding its final four-byte CRC:
  bytes 0–59 for Legacy or bytes 0–91 for `FULL-63`.
- Tags are one-byte-length-prefixed printable ASCII strings. The
  extension accepts one to eight unique tags of 1–32 bytes and validates its
  own CRC-32 before delivery.
- Record count is the unsigned 32-bit value at `headerSize`.
- Payload length must be an exact multiple of the detected record size, with no
  partial final record. Its actual record count must equal the manifest's
  declared count.
- CRC-32/ISO-HDLC of the first 12 manifest bytes equals its final four bytes.
- With records present, the first and last record sequence numbers match the
  manifest sequence-bound values.

An unknown profile is rejected before any record is decoded. The error includes
the on-wire profile identifier, schema version, and declared record size. A
known but disabled registry entry is also rejected explicitly. Truncated
headers, partial records, count mismatches, and checksum failures produce
separate errors.

The device ID is the unsigned value at header offset 12, formatted as six or
more upper-case hexadecimal digits after `RP-`. Delivery is enabled only after
all validation passes. The original optional RPB-to-NDJSON conversion was
disabled by configuration, so this replacement preserves the verified RPB-only
flow. The exact received bytes are retained for delivery; records are never
rewritten or translated.
