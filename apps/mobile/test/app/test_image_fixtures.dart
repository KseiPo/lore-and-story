import 'dart:convert';
import 'dart:typed_data';

/// A minimal, genuinely valid 1×1 transparent PNG — small enough to embed
/// verbatim, real enough for `Image.memory` to decode successfully. Shared by
/// every test that exercises Story 2.16's image loading (`markdown_preview_test.dart`,
/// `editor_page_test.dart`, `entity_detail_page_test.dart`) so the fixture
/// lives in exactly one place.
final Uint8List validPngFixture = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY'
  '42YAAAAASUVORK5CYII=',
);
