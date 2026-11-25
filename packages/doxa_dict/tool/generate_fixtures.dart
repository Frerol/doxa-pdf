// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

/// Regenerates the synthetic StarDict metadata fixture.
void main() {
  final fixture = File.fromUri(
    Platform.script.resolve('../test/fixtures/full.ifo'),
  );
  fixture.writeAsBytesSync(
    utf8.encode("""
StarDict's dict ifo file
version=3.0.0
bookname=Dicionário de teste
wordcount=2
idxfilesize=36
synwordcount=1
idxoffsetbits=64
sametypesequence=m
author=Test Author
email=test@example.org
website=https://example.org/?lang=pt
description=  a=b
date=2026-11-25
dicttype=example
lang=pt
custom=
"""),
  );
}
