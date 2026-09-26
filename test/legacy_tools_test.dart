import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wdm/util/legacy_tools.dart';

void main() {
  test('site grabber resolves and classifies links', () {
    final base = Uri.parse('https://example.test/folder/index.html');
    final links = SiteGrabber.extractLinks(
      '<a href="../files/a.zip">A</a><a href="/next/">Next</a>',
      base,
    );
    expect(links.map((e) => e.toString()), contains('https://example.test/files/a.zip'));
    expect(SiteGrabber.isDownloadCandidate(links.first), isTrue);
    expect(SiteGrabber.isDownloadCandidate(links.last), isFalse);
  });

  test('ZIP central directory parser lists entries', () {
    final name = utf8.encode('folder/file.txt');
    final bytes = Uint8List(46 + name.length);
    final data = ByteData.sublistView(bytes);

    data.setUint32(0, 0x02014b50, Endian.little);
    data.setUint16(8, 0x0800, Endian.little);
    data.setUint32(20, 50, Endian.little);
    data.setUint32(24, 100, Endian.little);
    data.setUint16(28, name.length, Endian.little);
    data.setUint16(30, 0, Endian.little);
    data.setUint16(32, 0, Endian.little);
    bytes.setRange(46, 46 + name.length, name);

    final entries = RemoteZipInspector.parseCentralDirectory(bytes, 1);
    expect(entries, hasLength(1));
    expect(entries.single.name, 'folder/file.txt');
    expect(entries.single.compressedSize, 50);
    expect(entries.single.uncompressedSize, 100);
    expect(entries.single.isDirectory, isFalse);
  });
}
