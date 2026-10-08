import 'package:flutter_test/flutter_test.dart';
import 'package:helpmemove/telemetry/product_event.dart';

void main() {
  const List<(String, Map<String, Object?>)> cases =
      <(String, Map<String, Object?>)>[
        ('screen_viewed', <String, Object?>{}),
        ('assessment_started', <String, Object?>{}),
        ('assessment_completed', <String, Object?>{}),
        ('exercise_started', <String, Object?>{}),
        ('exercise_completed', <String, Object?>{}),
        ('exercise_skipped', <String, Object?>{}),
        ('pain_reported', <String, Object?>{'region': 'shoulder', 'value': 7}),
        ('substitution_applied', <String, Object?>{}),
        ('session_completed', <String, Object?>{}),
        ('session_abandoned', <String, Object?>{}),
        ('movement_check_completed', <String, Object?>{}),
        ('program_changed', <String, Object?>{}),
        ('coach_action_requested', <String, Object?>{}),
        ('coach_action_applied', <String, Object?>{}),
        ('Application Opened', <String, Object?>{}),
        ('Application Backgrounded', <String, Object?>{}),
        ('Application Installed', <String, Object?>{}),
        ('Application Updated', <String, Object?>{}),
        (r'$screen', <String, Object?>{r'$screen_name': '/focus/intake'}),
        (r'$exception', <String, Object?>{}),
        (r'$pageview', <String, Object?>{}),
        (r'$snapshot', <String, Object?>{}),
        ('home_opened', <String, Object?>{}),
        ('privacy_opened', <String, Object?>{}),
        ('foundations_opened', <String, Object?>{}),
        ('', <String, Object?>{}),
        (
          'session_completed',
          <String, Object?>{'subject_id': 'subject-smoke-1'},
        ),
        ('screen_viewed', <String, Object?>{'route': '/focus/workout'}),
        ('   ', <String, Object?>{}),
        ('copied_pain', <String, Object?>{}),
        ('completed_count', <String, Object?>{}),
        ('abandoned_count', <String, Object?>{}),
        ('safety_stopped_count', <String, Object?>{}),
      ];

  test('admitProductEvent rejects every planned name', () {
    for (final (String name, Map<String, Object?> properties) in cases) {
      final ProductEventDecision decision = admitProductEvent(
        name: name,
        properties: properties,
      );
      expect(decision, ProductEventDecision.rejected, reason: name);
      expect(decision.name, 'rejected', reason: name);
    }
  });
}
