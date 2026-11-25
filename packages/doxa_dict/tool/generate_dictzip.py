# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate small StarDict data files with reproducible dictzip framing."""

from pathlib import Path
import struct
import zlib


def dictzip(data, chunk_length, *, optional_header=False):
    """Write one gzip member with independently inflatable chunks."""
    compressor = zlib.compressobj(wbits=-zlib.MAX_WBITS)
    chunks = []
    for offset in range(0, len(data), chunk_length):
        chunk = data[offset:offset + chunk_length]
        chunks.append(
            compressor.compress(chunk) + compressor.flush(zlib.Z_FULL_FLUSH)
        )
    sizes = [len(chunk) for chunk in chunks]
    table = struct.pack(f"<HHH{len(sizes)}H", 1, chunk_length, len(sizes), *sizes)
    extra = b"RA" + struct.pack("<H", len(table)) + table
    flags = 0x04
    if optional_header:
        flags |= 0x1A
        extra = b"XY\x01\x00!" + extra
    header = struct.pack("<BBBBIBB", 0x1F, 0x8B, 8, flags, 0, 0, 255)
    header += struct.pack("<H", len(extra)) + extra
    if optional_header:
        header += b"mixed.dict\0StarDict fixture\0"
        header += struct.pack("<H", zlib.crc32(header) & 0xFFFF)
    trailer = struct.pack("<II", zlib.crc32(data), len(data))
    return header + b"".join(chunks) + compressor.flush(zlib.Z_FINISH) + trailer


def main():
    fixtures = Path(__file__).resolve().parents[1] / "test" / "fixtures"
    text = "ação".encode()
    binary = b"\x00\xff\x10"
    binary_size = struct.pack(">I", len(binary))
    explicit = b"m" + text + b"\0W" + binary_size + binary
    implicit_binary_last = text + b"\0" + binary
    implicit_text_last = binary_size + binary + text
    data = explicit + implicit_binary_last + implicit_text_last
    (fixtures / "mixed.dict").write_bytes(data)
    (fixtures / "mixed.dict.dz").write_bytes(dictzip(data, 8))
    (fixtures / "mixed-header.dict.dz").write_bytes(
        dictzip(data, 8, optional_header=True)
    )


if __name__ == "__main__":
    main()
