import 'package:flutter/foundation.dart';
import 'package:helpmemove/account/account_auth.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:helpmemove/vision/movement_vision_session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AccountPhase {
  signedOut,
  confirmBind,
  signedIn,
  signOutChoice,
  switching,
  expired,
  accessRemoved,
  reauth,
}

const String copyInterruptedNotice =
    'The copy stopped. This phone still has the profile.';
const String copyCancelNotice = 'This profile stays on this phone.';

typedef CopySend = Future<String> Function({
  required String entity,
  required String eventId,
  required String documentText,
  required String documentSha256,
});

bool productionSessionReady() {
  if (!AccountAuth.started) {
    return false;
  }
  return Supabase.instance.client.auth.currentSession != null;
}

Future<String> productionSendCopy({
  required String entity,
  required String eventId,
  required String documentText,
  required String documentSha256,
}) async {
  // dart format off
  final Object? result = await Supabase.instance.client.rpc('copy_owned_document', params: <String, Object>{
    'p_entity': entity,
    'p_event_id': eventId,
    'p_document_text': documentText,
    'p_document_sha256': documentSha256,
  });
  // dart format on
  return '$result';
}

/// A listener the controller drops on switch and on sign-out.
class AccountSubscription {
  AccountSubscription(this.onEvent, this._onCancel);

  final void Function() onEvent;
  final void Function() _onCancel;
  bool cancelled = false;

  void cancel() {
    if (cancelled) {
      return;
    }
    cancelled = true;
    _onCancel();
  }
}

/// Binds one verified actor id to one local subject id.
///
/// The only stored mapping is `account-actor.<actorId>`. Email and name are
/// not written. [previousMarker] is retained for tests and is not rendered.
class AccountController extends ChangeNotifier {
  AccountController({
    required this.store,
    ProfileKeyStore? keys,
    CopySend? sendCopy,
    bool Function()? sessionReady,
  }) : keys = keys ?? store.keys,
       sendCopy = sendCopy ?? productionSendCopy,
       sessionReady = sessionReady ?? productionSessionReady;

  final ProfileStore store;
  final ProfileKeyStore keys;
  final CopySend sendCopy;
  final bool Function() sessionReady;

  AccountPhase phase = AccountPhase.signedOut;
  String? actorId;
  bool cloudAccess = false;
  int epoch = 0;
  String previousMarker = '';
  bool copyPreview = false;
  bool copyAccepted = false;
  String? copyNotice;
  int get generation => _generation;

  void Function()? _pending;
  String? _reauthActor;
  AccountPhase _phaseBeforeReauth = AccountPhase.signedIn;
  final List<AccountSubscription> _subscriptions = <AccountSubscription>[];
  int _generation = 0;
  Future<void> _pendingWork = Future<void>.value();
  AccountSubscription? _copyWorker;
  Future<void> _copyDispatch = Future<void>.value();
  bool _copyDraining = false;
  bool _copyRedrain = false;
  String? _copyActor;
  String? _copySubject;
  int _copyGeneration = 0;

  static String actorItem(String actorId) => 'account-actor.$actorId';

  Future<void> _serialized(Future<void> Function() action) {
    final Future<void> next = _pendingWork.then((_) => action());
    _pendingWork = next.then((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  AccountSubscription listen(void Function() onEvent) {
    late final AccountSubscription subscription;
    subscription = AccountSubscription(onEvent, () {
      _subscriptions.remove(subscription);
    });
    _subscriptions.add(subscription);
    return subscription;
  }

  void completeLate(int capturedEpoch, void Function() action) {
    if (capturedEpoch != epoch) {
      return;
    }
    action();
  }

  Future<void> presentActor(String actor) {
    final int generation = ++_generation;
    return _serialized(() async {
      if (generation != _generation) {
        return;
      }
      final String? subject = await keys.read(actorItem(actor));
      if (generation != _generation) {
        return;
      }
      actorId = actor;
      if (subject == null || subject.isEmpty) {
        _dropWork();
        copyPreview = false;
        copyAccepted = false;
        copyNotice = null;
        cloudAccess = false;
        phase = AccountPhase.signedOut;
        notifyListeners();
        return;
      }
      if (store.activeSubjectId == subject) {
        cloudAccess = true;
        phase = AccountPhase.signedIn;
        _enterSignedInCopy();
        notifyListeners();
        return;
      }
      final String? previous = store.activeSubjectId;
      await _switchToBoundSubject(subject, generation, actor, previous);
    });
  }

  void beginBind() {
    if (actorId == null) {
      return;
    }
    phase = AccountPhase.confirmBind;
    notifyListeners();
  }

  /// Leaves the actor unbound. Nothing is written.
  void cancelBind() {
    _generation += 1;
    phase = AccountPhase.signedOut;
    notifyListeners();
  }

  Future<void> confirmBind() {
    final int generation = _generation;
    final String? actor = actorId;
    return _serialized(() async {
      if (actor == null || generation != _generation || actorId != actor) {
        return;
      }
      final String? existing = await keys.read(actorItem(actor));
      if (generation != _generation || actorId != actor) {
        return;
      }
      final String? open = store.activeSubjectId;
      if (existing != null && existing.isNotEmpty && existing != open) {
        await _switchToBoundSubject(existing, generation, actor, open);
        return;
      }
      if (open == null || generation != _generation || actorId != actor) {
        return;
      }
      await keys.write(actorItem(actor), open);
      if (generation != _generation || actorId != actor) {
        await keys.delete(actorItem(actor));
        return;
      }
      cloudAccess = true;
      phase = AccountPhase.signedIn;
      _enterSignedInCopy();
      notifyListeners();
    });
  }

  void requestSignOut() {
    phase = AccountPhase.signOutChoice;
    notifyListeners();
  }

  Future<void> keepLocked() {
    final int generation = ++_generation;
    return _serialized(() async {
      _dropWork();
      copyNotice = null;
      copyPreview = false;
      copyAccepted = false;
      await store.lockOpenProfile();
      // The profile is already locked. Delete the session before the next
      // queued presentation, even when that presentation superseded this one
      // before this body started.
      await keys.delete(supabasePersistSessionKey);
      if (generation != _generation) {
        return;
      }
      actorId = null;
      cloudAccess = false;
      phase = AccountPhase.signedOut;
      notifyListeners();
    });
  }

  Future<void> removeLocal() {
    final int generation = ++_generation;
    final String? actor = actorId;
    final String? subject = store.activeSubjectId;
    return _serialized(() async {
      if (actor != null && subject != null) {
        final String? mapped = await keys.read(actorItem(actor));
        if (generation != _generation || mapped != subject) {
          return;
        }
      } else if (generation != _generation) {
        return;
      }
      // The pair is accepted. Finish this removal even if a newer
      // presentation arrives while the files are being deleted.
      _dropWork();
      copyNotice = null;
      copyPreview = false;
      copyAccepted = false;
      if (actor != null) {
        await keys.delete(actorItem(actor));
      }
      await keys.delete(supabasePersistSessionKey);
      if (subject != null) {
        await store.deleteSubjectFiles(subject);
      }
      await store.createProfile();
      if (generation != _generation) {
        return;
      }
      actorId = null;
      cloudAccess = false;
      phase = AccountPhase.signedOut;
      notifyListeners();
    });
  }

  Future<void> expire() {
    final int generation = ++_generation;
    return _serialized(() async {
      if (generation != _generation) {
        return;
      }
      _dropWork();
      cloudAccess = false;
      await keys.delete(supabasePersistSessionKey);
      if (generation != _generation) {
        return;
      }
      copyNotice = copyInterruptedNotice;
      phase = AccountPhase.expired;
      notifyListeners();
    });
  }

  Future<void> removeAccess() {
    final int generation = ++_generation;
    final String? actor = actorId;
    return _serialized(() async {
      if (generation != _generation) {
        return;
      }
      _dropWork();
      if (actor != null) {
        await keys.delete(actorItem(actor));
      }
      if (generation != _generation) {
        return;
      }
      actorId = null;
      cloudAccess = false;
      copyNotice = copyInterruptedNotice;
      phase = AccountPhase.accessRemoved;
      notifyListeners();
    });
  }

  void requestReauth(void Function() action) {
    _pending = action;
    _reauthActor = actorId;
    _phaseBeforeReauth = phase;
    phase = AccountPhase.reauth;
    notifyListeners();
  }

  void confirmReauth() {
    final void Function()? action = _pending;
    final String? expected = _reauthActor;
    _pending = null;
    _reauthActor = null;
    phase = _phaseBeforeReauth == AccountPhase.reauth
        ? AccountPhase.signedIn
        : _phaseBeforeReauth;
    if (action != null && expected != null && expected == actorId) {
      action();
    }
    notifyListeners();
  }

  void cancelReauth() {
    _pending = null;
    _reauthActor = null;
    phase = _phaseBeforeReauth == AccountPhase.reauth
        ? AccountPhase.signedIn
        : _phaseBeforeReauth;
    notifyListeners();
  }

  void openCopyPreview() {
    if (phase != AccountPhase.signedIn || store.activeSubjectId == null) {
      return;
    }
    if (copyPreview) {
      return;
    }
    copyPreview = true;
    copyNotice = null;
    _captureCopyContext();
    notifyListeners();
  }

  Future<void> bringItOver() async {
    await _serialized(() async {
      if (!copyPreview || phase != AccountPhase.signedIn) {
        return;
      }
      if (!_copyContextMatches()) {
        return;
      }
      try {
        await store.sweepCopyOutbox();
      } on Object {
        return;
      }
      final String? subject = store.activeSubjectId;
      if (subject == null || !_copyContextMatches()) {
        return;
      }
      try {
        await store.markCopyAccepted(subject);
      } on Object {
        return;
      }
      copyPreview = false;
      copyAccepted = true;
      _bindCopyWorker();
      notifyListeners();
    });
    await _copyDispatch;
  }

  void cancelCopy() {
    copyPreview = false;
    copyNotice = copyCancelNotice;
    notifyListeners();
  }

  Future<void> retryCopy() async {
    await _serialized(() async {
      if (!sessionReady()) {
        return;
      }
      _scheduleCopyDrain();
    });
    await _copyDispatch;
  }

  bool _owns(int generation, String actor) {
    return generation == _generation && actorId == actor;
  }

  Future<void> _restoreOrLock(String? previous) async {
    try {
      await _restorePrevious(previous);
    } on Object {
      await _lockIgnoringError();
    }
    if (store.activeSubjectId != previous) {
      await _lockIgnoringError();
    }
  }

  Future<void> _lockIgnoringError() async {
    try {
      await store.lockOpenProfile();
    } on Object {
      // The database is already closed when locking fails on the pointer.
    }
  }

  Future<void> _restorePrevious(String? previous) async {
    if (store.activeSubjectId == previous) {
      return;
    }
    if (previous == null) {
      await store.lockOpenProfile();
      return;
    }
    try {
      await store.switchTo(previous);
    } on Object {
      await store.lockOpenProfile();
    }
  }

  Future<void> _switchToBoundSubject(
    String subject,
    int generation,
    String actor,
    String? previous,
  ) async {
    if (!_owns(generation, actor)) {
      return;
    }
    previousMarker = 'previous-profile';
    _dropWork();
    phase = AccountPhase.switching;
    notifyListeners();
    try {
      await store.switchTo(
        subject,
        stillCurrent: () => _owns(generation, actor),
      );
    } on Object {
      Object? cleanupError;
      StackTrace? cleanupStack;
      try {
        if (_owns(generation, actor)) {
          await keys.delete(actorItem(actor));
        }
      } on Object catch (error, stackTrace) {
        cleanupError = error;
        cleanupStack = stackTrace;
      } finally {
        await _restoreOrLock(previous);
      }
      if (cleanupError != null) {
        Error.throwWithStackTrace(cleanupError, cleanupStack!);
      }
      if (!_owns(generation, actor)) {
        return;
      }
      actorId = null;
      cloudAccess = false;
      phase = AccountPhase.accessRemoved;
      notifyListeners();
    }
    if (!_owns(generation, actor)) {
      await _restorePrevious(previous);
      return;
    }
    cloudAccess = true;
    phase = AccountPhase.signedIn;
    _enterSignedInCopy();
    notifyListeners();
  }

  void _enterSignedInCopy() {
    final String? subject = store.activeSubjectId;
    if (subject != null && store.isCopyAccepted(subject)) {
      copyPreview = false;
      copyAccepted = true;
      _bindCopyWorker();
      return;
    }
    copyPreview = true;
    copyAccepted = false;
    copyNotice = null;
    _captureCopyContext();
  }

  void _captureCopyContext() {
    _copyActor = actorId;
    _copySubject = store.activeSubjectId;
    _copyGeneration = _generation;
  }

  bool _copyContextMatches() {
    return actorId == _copyActor &&
        store.activeSubjectId == _copySubject &&
        _generation == _copyGeneration;
  }

  void _bindCopyWorker() {
    _copyWorker?.cancel();
    late final AccountSubscription subscription;
    subscription = AccountSubscription(() {}, () {
      _subscriptions.remove(subscription);
      if (identical(_copyWorker, subscription)) {
        _copyWorker = null;
        store.onOutboxEnqueued = null;
      }
    });
    _subscriptions.add(subscription);
    _copyWorker = subscription;
    store.onOutboxEnqueued = _handleOutboxEnqueued;
    _scheduleCopyDrain();
  }

  void _handleOutboxEnqueued() {
    if (_copyDraining) {
      _copyRedrain = true;
    }
    _scheduleCopyDrain();
  }

  void _scheduleCopyDrain() {
    final Future<void> next = _copyDispatch.then((_) => _drainCopy());
    _copyDispatch = next.then((_) {}, onError: (Object _, StackTrace _) {});
  }

  Future<void> _drainCopy() async {
    _copyDraining = true;
    _copyRedrain = false;
    try {
      if (_copyWorker == null || _copyWorker!.cancelled) {
        return;
      }
      final String? subject = store.activeSubjectId;
      final String? actor = actorId;
      final int capturedGeneration = _generation;
      if (subject == null) {
        return;
      }
      final List<SyncOutboxPendingItem> pending = await store.loadPendingOutbox(
        subject,
      );
      if (!sessionReady()) {
        if (_postCheck(actor, subject, capturedGeneration)) {
          copyNotice = pending.isEmpty ? null : copyInterruptedNotice;
          notifyListeners();
        }
        return;
      }
      await _sendPending(subject, actor, capturedGeneration);
      while (_copyRedrain) {
        _copyRedrain = false;
        if (_copyWorker == null || _copyWorker!.cancelled) {
          return;
        }
        await _sendPending(subject, actor, capturedGeneration);
      }
      if (_copyWorker == null || _copyWorker!.cancelled) {
        return;
      }
      if (!_postCheck(actor, subject, capturedGeneration)) {
        return;
      }
      final List<SyncOutboxPendingItem> remaining = await store
          .loadPendingOutbox(subject);
      if (remaining.isEmpty) {
        copyNotice = null;
        notifyListeners();
      }
    } on Object {
      return;
    } finally {
      _copyDraining = false;
    }
  }

  Future<void> _sendPending(
    String subject,
    String? actor,
    int capturedGeneration,
  ) async {
    final List<SyncOutboxPendingItem> pending = await store.loadPendingOutbox(
      subject,
    );
    for (final SyncOutboxPendingItem item in pending) {
      if (_copyWorker == null || _copyWorker!.cancelled) {
        return;
      }
      await _sendOne(item, subject, actor, capturedGeneration);
    }
  }

  Future<void> _sendOne(
    SyncOutboxPendingItem item,
    String subject,
    String? actor,
    int capturedGeneration,
  ) async {
    final String sha = item.documentSha256;
    if (!_postCheck(actor, subject, capturedGeneration)) {
      return;
    }
    List<SyncOutboxPendingItem> latest;
    try {
      latest = await store.loadPendingOutbox(subject);
    } on Object {
      return;
    }
    SyncOutboxPendingItem? current;
    for (final SyncOutboxPendingItem row in latest) {
      if (row.eventId == item.eventId) {
        current = row;
        break;
      }
    }
    if (current == null || current.documentSha256 != sha) {
      return;
    }
    if (_copyWorker == null ||
        _copyWorker!.cancelled ||
        !_postCheck(actor, subject, capturedGeneration)) {
      return;
    }
    if (!sessionReady()) {
      if (_postCheck(actor, subject, capturedGeneration)) {
        copyNotice = copyInterruptedNotice;
        notifyListeners();
      }
      return;
    }
    String result;
    try {
      result = await sendCopy(
        entity: current.entity,
        eventId: current.eventId,
        documentText: current.documentJson,
        documentSha256: current.documentSha256,
      );
    } on Object {
      if (_postCheck(actor, subject, capturedGeneration)) {
        copyNotice = copyInterruptedNotice;
        notifyListeners();
      }
      return;
    }
    if (!_postCheck(actor, subject, capturedGeneration)) {
      return;
    }
    if (result == 'confirmed') {
      await store.markOutboxState(
        subjectId: subject,
        eventId: current.eventId,
        expectedSha: sha,
        state: 'confirmed',
      );
      return;
    }
    if (result == 'rejected') {
      await store.markOutboxState(
        subjectId: subject,
        eventId: current.eventId,
        expectedSha: sha,
        state: 'rejected',
      );
      return;
    }
    if (result == 'unavailable') {
      copyNotice = copyInterruptedNotice;
      notifyListeners();
    }
  }

  bool _postCheck(String? actor, String? subject, int capturedGeneration) {
    if (actorId != actor ||
        store.activeSubjectId != subject ||
        _generation != capturedGeneration ||
        subject == null ||
        !store.hasOpenDatabase) {
      return false;
    }
    return true;
  }

  void _dropWork() {
    MovementVisionSession.releaseInstalled();
    epoch += 1;
    final List<AccountSubscription> copy = List<AccountSubscription>.of(
      _subscriptions,
    );
    for (final AccountSubscription subscription in copy) {
      subscription.cancel();
    }
  }
}
