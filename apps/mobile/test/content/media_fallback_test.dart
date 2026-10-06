import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/content/media_fallback.dart';

void main() {
  test('resolveMediaFallback walks the ladder', () {
    expect(
      resolveMediaFallback(video: true, rive: true, still: true, text: true),
      MediaFallback.video,
    );
    expect(
      resolveMediaFallback(video: false, rive: true, still: true, text: true),
      MediaFallback.rive,
    );
    expect(
      resolveMediaFallback(video: false, rive: false, still: true, text: true),
      MediaFallback.still,
    );
    expect(
      resolveMediaFallback(video: false, rive: false, still: false, text: true),
      MediaFallback.text,
    );
    expect(
      resolveMediaFallback(
        video: false,
        rive: false,
        still: false,
        text: false,
      ),
      MediaFallback.unavailable,
    );
  });
}
