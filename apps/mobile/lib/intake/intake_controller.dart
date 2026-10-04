import 'package:helpmemove/intake/intake_draft.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';
import 'package:helpmemove/storage/profile_store.dart';

/// Owns one local draft and the synthetic rule call for the active profile.
class IntakeController {
  IntakeController({required this.store});

  final ProfileStore store;
  LocalIntakeDraft draft = LocalIntakeDraft();

  Future<void> load() async {
    final String? raw = await store.loadDraft();
    if (raw == null) {
      draft = LocalIntakeDraft();
      return;
    }
    draft = LocalIntakeDraft.decode(raw);
  }

  Future<void> save() async {
    await store.saveDraft(draft.encode());
  }

  Future<void> delete() async {
    await store.deleteDraft();
    draft = LocalIntakeDraft();
  }

  /// Sends schema acknowledgment only. Severity, note, and goals stay local.
  Future<SafetyView> classify() async {
    final List<SafetyAnswer> answers = <SafetyAnswer>[];
    if (draft.schemaAck == 'yes') {
      answers.add(const SafetyAnswer(token: 'schema_ack', value: 'yes'));
    }
    return classifyCommittedRule(
      answers: answers,
      nowUnixMillis: store.clock().toUtc().millisecondsSinceEpoch,
      triggers: const <String>[],
      emergencyRegion: '',
    );
  }
}
