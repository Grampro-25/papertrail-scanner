import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;
import 'package:papertrail/main.dart';

void main() {
  test('Rapid library saves commit the latest snapshot in order', () async {
    final root = await Directory.systemTemp.createTemp('papertrail_test_');
    try {
      final store = ScanStore()..root = root;
      final doc = ScanDoc(id: '1', name: 'Before', pages: ['page.jpg']);
      store.docs.add(doc);
      final first = store.save();
      doc.name = 'After';
      final second = store.save();
      await Future.wait([first, second]);
      final saved =
          jsonDecode(await File('${root.path}/index.json').readAsString())
              as List;
      expect(saved.single['name'], 'After');
      expect(await File('${root.path}/index.tmp').exists(), false);
    } finally {
      await File('${root.path}/index.json').delete();
      await root.delete();
    }
  });
  test('Documents retain metadata and page order when persisted', () {
    final doc = ScanDoc(
      id: '1',
      name: 'Receipt',
      pages: ['a.jpg', 'b.jpg'],
      category: 'Receipts',
      starred: true,
    );
    final restored = ScanDoc.fromJson(doc.toJson());
    expect(restored.pages, ['a.jpg', 'b.jpg']);
    expect(restored.starred, true);
    expect(restored.category, 'Receipts');
    expect(restored.created, doc.created);
  });
  test('Crop and rotation produce expected dimensions', () {
    final image = im.Image(width: 100, height: 200);
    im.fill(image, color: im.ColorRgb8(120, 90, 60));
    final output = processImage({
      'bytes': Uint8List.fromList(im.encodeJpg(image)),
      'turns': 1,
      'filter': 'Gray',
      'crop': <double>[0.25, 0, 0.75, 1],
    });
    final decoded = im.decodeJpg(output)!;
    expect(decoded.width, 100);
    expect(decoded.height, 100);
    final pixel = decoded.getPixel(50, 50);
    expect((pixel.r - pixel.g).abs(), lessThan(3));
  });
  test('Large imported images are bounded for device memory', () {
    final bytes = im.encodeJpg(im.Image(width: 2300, height: 100));
    final output = im.decodeJpg(normalizeImage(bytes))!;
    expect(output.width, 2200);
    expect(output.height, lessThan(100));
  });
}
