import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/assessment/assessment_document.dart';
import 'package:helpmemove/src/rust/frb_generated.dart';

void main() {
  setUpAll(() async {
    await RustLib.init();
  });

  test('document round-trips ratings and null skips', () {
    final LocalAssessment document = LocalAssessment(
      areas: const <AssessmentArea>[
        AssessmentArea(region: 'arm', laterality: 'left', rating: 'normal'),
        AssessmentArea(region: 'foot', laterality: 'bilateral', rating: null),
      ],
    );
    final LocalAssessment again = LocalAssessment.decode(document.encode());
    expect(again.areas, hasLength(2));
    expect(again.areas.first.rating, 'normal');
    expect(again.areas.last.rating, isNull);
    expect(again.stopped, isFalse);
    expect(again.complete, isFalse);
  });

  test('decode rejects extra keys, braces, and a forged complete flag', () {
    const String extra =
        '{"record_version":1,"instrument_id":"syn-assessment-core","instrument_version":1,"areas":[],"stopped":false,"complete":false,"not_in_the_error":1}';
    try {
      LocalAssessment.decode(extra);
      fail('decoded an extra key');
    } on LocalAssessmentException catch (error) {
      expect(error.toString().contains('not_in_the_error'), isFalse);
    }

    expect(
      () => LocalAssessment.decode('{'),
      throwsA(isA<LocalAssessmentException>()),
    );
    try {
      LocalAssessment.decode('{');
      fail('decoded a brace');
    } on LocalAssessmentException catch (error) {
      expect(error.toString().contains('{'), isFalse);
    }

    const String forged =
        '{"record_version":1,"instrument_id":"syn-assessment-core","instrument_version":1,"areas":[{"region":"arm","laterality":"left","rating":null}],"stopped":false,"complete":true}';
    expect(
      () => LocalAssessment.decode(forged),
      throwsA(isA<LocalAssessmentException>()),
    );

    const String duplicate =
        '{"record_version":1,"instrument_id":"syn-assessment-core","instrument_version":1,"areas":[{"region":"arm","laterality":"left","rating":"normal"},{"region":"arm","laterality":"right","rating":"limited"}],"stopped":false,"complete":false}';
    expect(
      () => LocalAssessment.decode(duplicate),
      throwsA(isA<LocalAssessmentException>()),
    );
  });
}
