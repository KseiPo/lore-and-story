import 'package:flutter_test/flutter_test.dart';
import 'package:lore_and_story/lore/lore.dart';

void main() {
  group('rewriteRelativeImagePaths (Story 5.1)', () {
    test('a plain relative src gets ../ prepended', () {
      final result = rewriteRelativeImagePaths('![Frank](media/frank.jpg)');
      expect(result, '![Frank](../media/frank.jpg)');
    });

    test('an already ../-relative src gets a second ../ prepended', () {
      final result =
          rewriteRelativeImagePaths('![Logo](../shared/logo.png)');
      expect(result, '![Logo](../../shared/logo.png)');
    });

    test('a subfolder-relative src is rewritten correctly', () {
      final result =
          rewriteRelativeImagePaths('![Close-up](media/portraits/x.jpg)');
      expect(result, '![Close-up](../media/portraits/x.jpg)');
    });

    test('an http:// src is left untouched', () {
      const text = '![Remote](http://example.com/hero.png)';
      expect(rewriteRelativeImagePaths(text), text);
    });

    test('an https:// src is left untouched', () {
      const text = '![Remote](https://example.com/hero.png)';
      expect(rewriteRelativeImagePaths(text), text);
    });

    test('a leading-/ absolute src is left untouched', () {
      const text = '![Abs](/etc/hero.png)';
      expect(rewriteRelativeImagePaths(text), text);
    });

    test('a Windows drive-letter absolute src is left untouched', () {
      const text = r'![Abs](C:\images\hero.png)';
      expect(rewriteRelativeImagePaths(text), text);
    });

    test('content with no images returns unchanged', () {
      const text = '# Frank\n\nJust some prose, no pictures here.';
      expect(rewriteRelativeImagePaths(text), text);
    });

    test('malformed image markup (no closing paren) returns unchanged, never throws', () {
      const text = '# Frank\n\n![broken](media/x.jpg\n\nmore text after';
      expect(rewriteRelativeImagePaths(text), text);
    });

    test('multiple images are each rewritten independently; surrounding text preserved',
        () {
      const text = '# Frank\n\n'
          'Intro paragraph.\n\n'
          '![One](media/one.jpg)\n\n'
          'Middle prose stays untouched — including a [wikilink] and (parens).\n\n'
          '![Two](../shared/two.png)\n\n'
          'Trailing prose.\n';
      final result = rewriteRelativeImagePaths(text);
      expect(result, '# Frank\n\n'
          'Intro paragraph.\n\n'
          '![One](../media/one.jpg)\n\n'
          'Middle prose stays untouched — including a [wikilink] and (parens).\n\n'
          '![Two](../../shared/two.png)\n\n'
          'Trailing prose.\n');
    });

    test('a title after the src is preserved verbatim', () {
      final result =
          rewriteRelativeImagePaths('![Frank](media/frank.jpg "Frank\'s portrait")');
      expect(result, '![Frank](../media/frank.jpg "Frank\'s portrait")');
    });

    test('an empty string returns unchanged', () {
      expect(rewriteRelativeImagePaths(''), '');
    });
  });
}
