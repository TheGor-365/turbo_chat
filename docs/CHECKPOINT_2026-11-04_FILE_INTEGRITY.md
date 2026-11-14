# P0 checkpoint — bounded whole-file structure screening

Date: 2026-11-04. Add an explicit full-byte integrity screen to the
existing MIME/signature checker, after the 5 MB per-file cap.

- UTF-8 text: checks the **entire file** for invalid encoding and NUL,
  not just the first 4096 bytes.
- PNG: verifies chunk boundaries, order of mandatory IHDR/IDAT/IEND,
  CRC32 checksums and a conservative maximum of 8192 px per side /
  16 million pixels, without decompressing image data.
- WebP: verifies RIFF container byte count, initial chunk type and size.
- JPEG: checks for an end-of-image marker near the end.
- PDF: checks header version and final EOF marker envelope.

This does NOT confirm complete PDF object/xref integrity, decode JPEG/WebP/
PNG pixels, prove absence of malicious content or implement a malware scanner.
It is intentionally called structural screening, not 'safe file' certification.
Corrupt and oversized examples are covered by regression tests. Production
decoder sandboxing, limits on decompression/CPU, AV scanning as appropriate,
and private storage/backup remain release gates.
