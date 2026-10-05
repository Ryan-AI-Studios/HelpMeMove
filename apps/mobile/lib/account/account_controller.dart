import 'package:flutter/foundation.dart';
import 'package:helpmemove/storage/profile_key_store.dart';
import 'package:helpmemove/storage/profile_store.dart';
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
  AccountController({required this.store, ProfileKeyStore? keys})
    : keys = keys ?? store.keys;

  final ProfileStore store;
  final ProfileKeyStore keys;

  AccountPhase phase = AccountPhase.signedOut;
  String? actorId;
  bool cloudAccess = false;
  int epoch = 0;
  String previousMarker = '';

  void Function()? _pending;
  String? _reauthActor;
  AccountPhase _phaseBeforeReauth = AccountPhase.signedIn;
  final List<AccountSubscription> _subscriptions = <AccountSubscription>[];
  int _generation = 0;
  Future<void> _pendingWork = Future<void>.value();

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
        cloudAccess = false;
        phase = AccountPhase.signedOut;
        notifyListeners();
        return;
      }
      if (store.activeSubjectId == subject) {
        cloudAccess = true;
        phase = AccountPhase.signedIn;
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
      cloudAccess = false;
      await keys.delete(supabasePersistSessionKey);
      if (generation != _generation) {
        return;
      }
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
      if (actor != null) {
        await keys.delete(actorItem(actor));
      }
      if (generation != _generation) {
        return;
      }
      actorId = null;
      cloudAccess = false;
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
    notifyListeners();
  }

  void _dropWork() {
    epoch += 1;
    final List<AccountSubscription> copy = List<AccountSubscription>.of(
      _subscriptions,
    );
    for (final AccountSubscription subscription in copy) {
      subscription.cancel();
    }
  }
}
