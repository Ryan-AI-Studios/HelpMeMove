import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:helpmemove/account/account_auth.dart';
import 'package:helpmemove/account/phone_unlock.dart';
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
  exportPreview,
  exportResult,
  deletePreview,
  deleteResult,
}

enum ExportResult { cancelled, saved, notSaved }

enum DeleteResult {
  cancelled,
  stillHere,
  signInRemoved,
  removed,
  removedWithSignIn,
  notReplaced,
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

typedef DeleteRpc = Future<String> Function();

typedef SignOutAction = Future<void> Function();

typedef StopRefresh = void Function();

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

Future<String> productionDeleteRpc() async {
  if (!AccountAuth.started) {
    return 'unavailable';
  }
  final Object? result = await Supabase.instance.client.rpc(
    'delete_personal_actor',
  );
  if (result is String) {
    return result;
  }
  return '$result';
}

Future<void> productionSignOut() async {
  if (!AccountAuth.started) {
    return;
  }
  await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
}

void productionStopRefresh() {
  if (!AccountAuth.started) {
    return;
  }
  Supabase.instance.client.auth.stopAutoRefresh();
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
    DeleteRpc? deleteRpc,
    SignOutAction? signOutAction,
    StopRefresh? stopRefresh,
    PhoneUnlock? phoneUnlock,
  }) : keys = keys ?? store.keys,
       sendCopy = sendCopy ?? productionSendCopy,
       sessionReady = sessionReady ?? productionSessionReady,
       deleteRpc = deleteRpc ?? productionDeleteRpc,
       signOutAction = signOutAction ?? productionSignOut,
       stopRefresh = stopRefresh ?? productionStopRefresh,
       phoneUnlock = phoneUnlock ?? ProductionPhoneUnlock();

  final ProfileStore store;
  final ProfileKeyStore keys;
  final CopySend sendCopy;
  final bool Function() sessionReady;
  final DeleteRpc deleteRpc;
  final SignOutAction signOutAction;
  final StopRefresh stopRefresh;
  final PhoneUnlock phoneUnlock;

  AccountPhase phase = AccountPhase.signedOut;
  String? actorId;
  bool cloudAccess = false;
  int epoch = 0;
  String previousMarker = '';
  bool copyPreview = false;
  bool copyAccepted = false;
  String? copyNotice;
  ExportResult? exportResult;
  DeleteResult? deleteResult;
  bool confirmInFlight = false;
  bool rpcDispatched = false;
  bool accountRouteOpen = false;
  PhoneUnlockGate unlockGate = PhoneUnlockGate.ready;
  int get generation => _generation;

  int _advanceGeneration() {
    _generation += 1;
    _releaseCopyWorker();
    return _generation;
  }

  void _releaseCopyWorker() {
    _copyWorker?.cancel();
    store.onOutboxEnqueued = null;
  }

  bool get isSessionPresent => sessionReady();
  bool get rpcCommitted => _rpcCommitted;
  bool get namesSignInRemoval => _previewActor != null && isSessionPresent;

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
  bool _deleteCancelled = false;
  bool _exportCancelled = false;
  bool _rpcCommitted = false;
  bool _unlocking = false;
  int _unlockTicket = 0;
  String? _previewActor;
  String? _previewSubject;
  int _previewGeneration = 0;
  AccountPhase _previewPhase = AccountPhase.signedOut;

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
    final int generation = _advanceGeneration();
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
    _advanceGeneration();
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
    final int generation = _advanceGeneration();
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
    final int generation = _advanceGeneration();
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
    final int generation = _advanceGeneration();
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
    final int generation = _advanceGeneration();
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
      if (!copyPreview || !_copyContextMatches()) {
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
      if (!copyPreview || !_copyContextMatches()) {
        store.clearCopyAccepted(subject);
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
      if (!sessionReady()) {
        if (_postCheck(actor, subject, capturedGeneration)) {
          final bool pendingRow = await store.hasPendingOutbox(subject);
          if (_postCheck(actor, subject, capturedGeneration)) {
            copyNotice = pendingRow ? copyInterruptedNotice : null;
            notifyListeners();
          }
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
      final bool pendingRow = await store.hasPendingOutbox(subject);
      if (!_postCheck(actor, subject, capturedGeneration)) {
        return;
      }
      if (!pendingRow) {
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
    _rpcCommitted = false;
    MovementVisionSession.releaseInstalled();
    epoch += 1;
    final List<AccountSubscription> copy = List<AccountSubscription>.of(
      _subscriptions,
    );
    for (final AccountSubscription subscription in copy) {
      subscription.cancel();
    }
  }

  Future<void> openExportPreview() async {
    final String? subject = store.activeSubjectId;
    if (subject == null) {
      return;
    }
    if (phase != AccountPhase.exportPreview) {
      _capturePreview();
      exportResult = null;
      deleteResult = null;
      phase = AccountPhase.exportPreview;
    }
    _exportCancelled = false;
    unlockGate = PhoneUnlockGate.checking;
    notifyListeners();
    unawaited(store.deleteExport(subject).catchError((Object _) {}));
    await _refreshUnlock();
  }

  Future<void> openDeletePreview() async {
    final String? subject = store.activeSubjectId;
    if (subject == null) {
      return;
    }
    if (phase != AccountPhase.deletePreview) {
      _capturePreview();
      exportResult = null;
      deleteResult = null;
      phase = AccountPhase.deletePreview;
    }
    _deleteCancelled = false;
    _rpcCommitted = false;
    unlockGate = PhoneUnlockGate.checking;
    notifyListeners();
    await _refreshUnlock();
  }

  void cancelExport() {
    _exportCancelled = true;
    unawaited(store.deleteExport(_previewSubject).catchError((Object _) {}));
    if (confirmInFlight) {
      return;
    }
    if (!accountRouteOpen) {
      return;
    }
    exportResult = ExportResult.cancelled;
    deleteResult = null;
    phase = AccountPhase.exportResult;
    notifyListeners();
  }

  void cancelDelete() {
    unawaited(store.deleteExport(_previewSubject).catchError((Object _) {}));
    _deleteCancelled = true;
    if (confirmInFlight) {
      if (rpcDispatched) {
        _deleteCancelled = false;
      }
      return;
    }
    if (!accountRouteOpen) {
      return;
    }
    deleteResult = DeleteResult.cancelled;
    exportResult = null;
    phase = AccountPhase.deleteResult;
    notifyListeners();
  }

  Future<void> confirmExport() async {
    if (_unlocking || confirmInFlight) {
      return;
    }
    _exportCancelled = false;
    confirmInFlight = true;
    notifyListeners();
    try {
      final PhoneUnlockDecision decision = await _promptUnlock();
      if (_exportCancelled) {
        if (accountRouteOpen) {
          exportResult = ExportResult.cancelled;
          deleteResult = null;
          phase = AccountPhase.exportResult;
        }
        return;
      }
      if (!_previewStillCurrent()) {
        return;
      }
      if (decision != PhoneUnlockDecision.confirmed) {
        _showUnlockDecision(decision);
        return;
      }
      unlockGate = PhoneUnlockGate.ready;
      await _serialized(_confirmExportBody);
    } finally {
      confirmInFlight = false;
      notifyListeners();
    }
  }

  Future<void> confirmDelete() async {
    if (_unlocking || confirmInFlight) {
      return;
    }
    _deleteCancelled = false;
    confirmInFlight = true;
    notifyListeners();
    try {
      final PhoneUnlockDecision decision = await _promptUnlock();
      if (_deleteCancelled) {
        if (accountRouteOpen) {
          deleteResult = DeleteResult.cancelled;
          exportResult = null;
          phase = AccountPhase.deleteResult;
        }
        return;
      }
      if (!_previewStillCurrent()) {
        return;
      }
      if (decision != PhoneUnlockDecision.confirmed) {
        _showUnlockDecision(decision);
        return;
      }
      unlockGate = PhoneUnlockGate.ready;
      await _serialized(_confirmDeleteBody);
    } finally {
      confirmInFlight = false;
      rpcDispatched = false;
      _deleteCancelled = false;
      notifyListeners();
    }
  }

  Future<void> retryLocalDelete() {
    if (confirmInFlight || deleteResult != DeleteResult.signInRemoved) {
      return Future<void>.value();
    }
    confirmInFlight = true;
    notifyListeners();
    return _serialized(() async {
      try {
        if (deleteResult != DeleteResult.signInRemoved) {
          return;
        }
        final String? subject = _previewSubject;
        if (subject == null) {
          return;
        }
        final LocalRemoval removal = await store.removeSubjectDirectoryFirst(
          subject,
        );
        if (!accountRouteOpen) {
          exportResult = null;
          deleteResult = null;
          if (removal != LocalRemoval.directoryRemained) {
            phase = AccountPhase.signedOut;
          }
          return;
        }
        phase = AccountPhase.deleteResult;
        if (removal == LocalRemoval.directoryRemained) {
          deleteResult = DeleteResult.signInRemoved;
        } else if (removal == LocalRemoval.replaced) {
          deleteResult = DeleteResult.removedWithSignIn;
        } else {
          deleteResult = DeleteResult.notReplaced;
        }
      } finally {
        _resetConfirmFlags();
        notifyListeners();
      }
    });
  }

  Future<void> retryCreateProfile() {
    if (confirmInFlight || deleteResult != DeleteResult.notReplaced) {
      return Future<void>.value();
    }
    confirmInFlight = true;
    notifyListeners();
    return _serialized(() async {
      try {
        if (deleteResult != DeleteResult.notReplaced) {
          return;
        }
        try {
          await store.createProfile();
          if (!accountRouteOpen) {
            exportResult = null;
            deleteResult = null;
            phase = AccountPhase.signedOut;
            return;
          }
          deleteResult = _rpcCommitted
              ? DeleteResult.removedWithSignIn
              : DeleteResult.removed;
          phase = AccountPhase.deleteResult;
        } on Object {
          if (!accountRouteOpen) {
            exportResult = null;
            deleteResult = null;
            return;
          }
          deleteResult = DeleteResult.notReplaced;
          phase = AccountPhase.deleteResult;
        }
      } finally {
        _resetConfirmFlags();
        notifyListeners();
      }
    });
  }

  void dismissResult() {
    final DeleteResult? deleting = deleteResult;
    exportResult = null;
    deleteResult = null;
    accountRouteOpen = false;
    _rpcCommitted = false;
    phase = _terminalDelete(deleting) ? AccountPhase.signedOut : _previewPhase;
    notifyListeners();
  }

  void closeAccountRoute({bool notify = true}) {
    unawaited(store.deleteExport().catchError((Object _) {}));
    final DeleteResult? deleting = deleteResult;
    final bool terminal = _terminalDelete(deleting);
    exportResult = null;
    deleteResult = null;
    accountRouteOpen = false;
    if (phase == AccountPhase.exportPreview ||
        phase == AccountPhase.exportResult ||
        phase == AccountPhase.deletePreview ||
        (phase == AccountPhase.deleteResult && !terminal)) {
      phase = _previewPhase;
    } else if (phase == AccountPhase.deleteResult && terminal) {
      phase = AccountPhase.signedOut;
    }
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> _confirmExportBody() async {
    if (_exportCancelled) {
      if (accountRouteOpen) {
        exportResult = ExportResult.cancelled;
        deleteResult = null;
        phase = AccountPhase.exportResult;
      }
      return;
    }
    if (!_previewStillCurrent() || !accountRouteOpen) {
      return;
    }
    confirmInFlight = true;
    _exportCancelled = false;
    phase = AccountPhase.exportPreview;
    notifyListeners();
    try {
      var wrote = false;
      try {
        await store.writeExport();
        wrote = true;
      } on Object {
        if (accountRouteOpen) {
          exportResult = ExportResult.notSaved;
          phase = AccountPhase.exportResult;
        }
        return;
      }
      final bool abandon =
          _exportCancelled || !accountRouteOpen || !_previewStillCurrent();
      if (wrote && abandon) {
        await store.deleteExport(_previewSubject);
      }
      if (!accountRouteOpen) {
        return;
      }
      if (abandon) {
        exportResult = ExportResult.cancelled;
        phase = AccountPhase.exportResult;
        return;
      }
      exportResult = ExportResult.saved;
      phase = AccountPhase.exportResult;
    } finally {
      confirmInFlight = false;
      notifyListeners();
    }
  }

  Future<void> _confirmDeleteBody() async {
    if (_deleteCancelled) {
      if (accountRouteOpen) {
        deleteResult = DeleteResult.cancelled;
        exportResult = null;
        phase = AccountPhase.deleteResult;
      }
      return;
    }
    if (!_previewStillCurrent() || !accountRouteOpen) {
      return;
    }
    confirmInFlight = true;
    _deleteCancelled = false;
    _rpcCommitted = false;
    phase = AccountPhase.deletePreview;
    notifyListeners();
    var cleared = false;
    try {
      await store.deleteExport(_previewSubject);
      if (!_previewStillCurrent()) {
        return;
      }
      final bool sessionPath = _previewActor != null && isSessionPresent;
      if (sessionPath) {
        if (!_continueDelete()) {
          _stopBeforeRpc();
          return;
        }
        rpcDispatched = true;
        notifyListeners();
        if (!_continueDelete() || !_previewStillCurrent()) {
          if (_previewStillCurrent()) {
            _stopBeforeRpc();
          }
          return;
        }
        final String rpcText = await _readDeleteRpc();
        final bool committed = rpcText == 'deleted';
        if (committed) {
          _rpcCommitted = true;
          await _clearCommittedSignIn();
          cleared = true;
        }
        if (!_previewStillCurrent()) {
          if (committed) {
            final LocalRemoval removal = await store
                .removeSubjectDirectoryFirst(_previewSubject!);
            _publishRemoval(removal, committed: true, cleared: true);
          }
          return;
        }
        if (!committed) {
          if (accountRouteOpen) {
            deleteResult = DeleteResult.stillHere;
            phase = AccountPhase.deleteResult;
          } else {
            _leaveClosedDelete(cleared: false);
          }
          return;
        }
        final LocalRemoval removal = await store.removeSubjectDirectoryFirst(
          _previewSubject!,
        );
        _publishRemoval(removal, committed: true, cleared: true);
        return;
      }
      if (!accountRouteOpen) {
        _leaveClosedDelete(cleared: false);
        return;
      }
      if (_deleteCancelled) {
        deleteResult = DeleteResult.cancelled;
        phase = AccountPhase.deleteResult;
        return;
      }
      if (!_previewStillCurrent()) {
        return;
      }
      final LocalRemoval removal = await store.removeSubjectDirectoryFirst(
        _previewSubject!,
      );
      if (removal != LocalRemoval.directoryRemained && _previewActor != null) {
        await _clearLocalActor();
        cleared = true;
      }
      _publishRemoval(removal, committed: false, cleared: cleared);
    } finally {
      _resetConfirmFlags();
      notifyListeners();
    }
  }

  bool _continueDelete() {
    return !_deleteCancelled && accountRouteOpen;
  }

  void _stopBeforeRpc() {
    if (!accountRouteOpen) {
      _leaveClosedDelete(cleared: false);
      return;
    }
    if (_deleteCancelled) {
      deleteResult = DeleteResult.cancelled;
      phase = AccountPhase.deleteResult;
    }
  }

  Future<String> _readDeleteRpc() async {
    try {
      return await deleteRpc();
    } on Object {
      return '';
    }
  }

  void _publishRemoval(
    LocalRemoval removal, {
    required bool committed,
    required bool cleared,
  }) {
    if (!accountRouteOpen) {
      _leaveClosedDelete(
        cleared: cleared || removal != LocalRemoval.directoryRemained,
      );
      return;
    }
    phase = AccountPhase.deleteResult;
    if (removal == LocalRemoval.directoryRemained) {
      deleteResult = committed
          ? DeleteResult.signInRemoved
          : DeleteResult.stillHere;
      return;
    }
    if (removal == LocalRemoval.notReplaced) {
      deleteResult = DeleteResult.notReplaced;
      return;
    }
    deleteResult = committed
        ? DeleteResult.removedWithSignIn
        : DeleteResult.removed;
  }

  void _leaveClosedDelete({required bool cleared}) {
    exportResult = null;
    deleteResult = null;
    phase = cleared ? AccountPhase.signedOut : _previewPhase;
  }

  Future<void> _clearCommittedSignIn() async {
    if (AccountAuth.started) {
      try {
        await signOutAction();
      } on Object {
        // A thrown sign-out does not undo a committed delete.
      }
      try {
        stopRefresh();
      } on Object {
        // The session key is still removed after the timer call.
      }
    }
    await _clearLocalActor();
  }

  Future<void> _clearLocalActor() async {
    final String? actor = _previewActor;
    if (actor != null) {
      try {
        await keys.delete(actorItem(actor));
      } on Object {
        // A thrown actor-key delete still continues committed cleanup.
      }
    }
    try {
      await keys.delete(supabasePersistSessionKey);
    } on Object {
      // A thrown session-key delete still continues committed cleanup.
    }
    actorId = null;
    cloudAccess = false;
  }

  void _resetConfirmFlags() {
    confirmInFlight = false;
    rpcDispatched = false;
    _deleteCancelled = false;
  }

  Future<PhoneUnlockDecision> _promptUnlock() async {
    _unlocking = true;
    try {
      return await phoneUnlock.authenticate();
    } on Object {
      return PhoneUnlockDecision.unfinished;
    } finally {
      _unlocking = false;
    }
  }

  void _showUnlockDecision(PhoneUnlockDecision decision) {
    switch (decision) {
      case PhoneUnlockDecision.confirmed:
        unlockGate = PhoneUnlockGate.ready;
      case PhoneUnlockDecision.canceled:
        unlockGate = PhoneUnlockGate.canceled;
      case PhoneUnlockDecision.unfinished:
        unlockGate = PhoneUnlockGate.unfinished;
      case PhoneUnlockDecision.unavailable:
        unlockGate = PhoneUnlockGate.unavailable;
    }
    notifyListeners();
  }

  Future<void> _refreshUnlock() async {
    final int ticket = ++_unlockTicket;
    PhoneUnlockSupport support;
    try {
      support = await phoneUnlock.isDeviceSupported();
    } on Object {
      support = PhoneUnlockSupport.unfinished;
    }
    if (ticket != _unlockTicket) {
      return;
    }
    if (phase != AccountPhase.exportPreview &&
        phase != AccountPhase.deletePreview) {
      return;
    }
    switch (support) {
      case PhoneUnlockSupport.ready:
        unlockGate = PhoneUnlockGate.ready;
      case PhoneUnlockSupport.unavailable:
        unlockGate = PhoneUnlockGate.unavailable;
      case PhoneUnlockSupport.unfinished:
        unlockGate = PhoneUnlockGate.unfinished;
    }
    notifyListeners();
  }

  void _capturePreview() {
    _previewActor = actorId;
    _previewSubject = store.activeSubjectId;
    _previewGeneration = _generation;
    _previewPhase = phase;
  }

  bool _previewStillCurrent() {
    if (_previewSubject == null || store.activeSubjectId != _previewSubject) {
      return false;
    }
    if (_generation != _previewGeneration) {
      return false;
    }
    if (_previewActor == null) {
      return actorId == null;
    }
    return actorId == _previewActor;
  }

  bool _terminalDelete(DeleteResult? result) {
    return result == DeleteResult.signInRemoved ||
        result == DeleteResult.removed ||
        result == DeleteResult.removedWithSignIn ||
        result == DeleteResult.notReplaced;
  }
}
