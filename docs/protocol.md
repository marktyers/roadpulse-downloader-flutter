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

## RPB validation before delivery

All integers are little-endian. The binary payload must satisfy:

- At least 80 bytes: 64-byte header plus 16-byte manifest.
- Header magic at offset 0 is `0x48425052` (`RPBH` on disk).
- Header size at offset 6 is 64; record size at offset 10 is 41.
- Byte 47 is 1 (the supported stored-record layout marker).
- CRC-32/ISO-HDLC of bytes 0–59 equals the value at offset 60.
- Record count is the unsigned 32-bit value at offset 64.
- Exact length is `64 + 16 + recordCount * 41`.
- CRC-32/ISO-HDLC of manifest bytes 64–75 equals offset 76.
- With records present, the first and last record sequence numbers match the
  manifest values at offsets 68 and 72.

The device ID is the unsigned value at header offset 12, formatted as six or
more upper-case hexadecimal digits after `RP-`. Delivery is enabled only after
all validation passes. The original optional RPB-to-NDJSON conversion was
disabled by configuration, so this replacement preserves the verified RPB-only
flow.
