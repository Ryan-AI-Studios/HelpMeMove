import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/account/account_controller.dart';
import 'package:helpmemove/account/phone_unlock.dart';
import 'package:helpmemove/design/app_spacing.dart';
import 'package:helpmemove/design/components/primary_button.dart';

/// A route query carrying a token, email, or session is not an account page.
bool accountLinkIsUnavailable(Uri uri) {
  for (final String key in const <String>['token', 'email', 'session']) {
    final String value = uri.queryParameters[key] ?? '';
    if (value.isNotEmpty) {
      return true;
    }
  }
  return false;
}

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, this.controller, this.unavailable = false});

  final AccountController? controller;
  final bool unavailable;

  @override
  State<AccountScreen> createState() => AccountScreenState();
}

class AccountScreenState extends State<AccountScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller?.accountRouteOpen = true;
  }

  @override
  void dispose() {
    widget.controller?.closeAccountRoute(notify: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AccountController? account = widget.controller;
    return RepaintBoundary(
      key: const Key('account-capture'),
      child: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Scaffold(
          body: SafeArea(
            child: widget.unavailable || account == null
                ? const _AccountScroll(
                    children: <Widget>[Text('That page is unavailable.')],
                  )
                : ListenableBuilder(
                    listenable: account,
                    builder: (BuildContext context, Widget? child) {
                      return _AccountScroll(
                        children: _children(context, account),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  List<Widget> _children(BuildContext context, AccountController account) {
    if (account.phase == AccountPhase.exportPreview ||
        account.phase == AccountPhase.exportResult) {
      return _exportChildren(context, account);
    }
    if (account.phase == AccountPhase.deletePreview ||
        account.phase == AccountPhase.deleteResult) {
      return _deleteChildren(context, account);
    }
    if (account.phase == AccountPhase.signedIn && account.copyPreview) {
      return <Widget>[
        const Text('Bring this profile to the signed-in account?'),
        const Text(
          'This phone keeps the profile until you confirm. Nothing is uploaded until you confirm.',
        ),
        PrimaryButton(
          label: 'Bring it over',
          onPressed: () => unawaited(account.bringItOver()),
        ),
        PrimaryButton(label: 'Not now', onPressed: account.cancelCopy),
      ];
    }
    final List<Widget> children = List<Widget>.of(
      _phaseChildren(context, account),
    );
    final String? notice = account.copyNotice;
    if (notice != null) {
      children.add(Text(notice));
      if (notice == copyInterruptedNotice) {
        children.add(
          PrimaryButton(
            label: 'Try again',
            onPressed: () => unawaited(account.retryCopy()),
          ),
        );
      }
    }
    return children;
  }

  List<Widget> _exportChildren(
    BuildContext context,
    AccountController account,
  ) {
    if (account.phase == AccountPhase.exportResult) {
      return _exportResult(context, account);
    }
    const String body =
        'The file has the profile, assessments, programs, and workouts on this phone. Nothing is uploaded. The copy is not encrypted. This build does not open a share sheet. The file is removed when you leave this screen. If the app closes first, the next launch removes it.';
    final List<Widget> children = <Widget>[
      const Text('Save a copy of this profile?'),
      const Text(body),
    ];
    if (account.unlockGate == PhoneUnlockGate.checking) {
      children.add(const Text("Checking this phone's unlock."));
      return children;
    }
    if (account.unlockGate == PhoneUnlockGate.unavailable) {
      children.add(
        const Text(
          "This phone has no unlock check, so this action is unavailable.",
        ),
      );
      children.add(
        PrimaryButton(label: 'Not now', onPressed: account.cancelExport),
      );
      return children;
    }
    if (account.unlockGate == PhoneUnlockGate.canceled) {
      children.add(const Text('Nothing was saved or removed.'));
    } else if (account.unlockGate == PhoneUnlockGate.unfinished) {
      children.add(
        const Text(
          'The phone unlock check did not finish. Nothing was saved or removed.',
        ),
      );
    }
    if (account.confirmInFlight) {
      children.add(const Text('Preparing the file on this phone.'));
      children.add(
        PrimaryButton(label: 'Not now', onPressed: account.cancelExport),
      );
      return children;
    }
    children.add(
      PrimaryButton(
        label: 'Prepare the file',
        onPressed: () => unawaited(account.confirmExport()),
      ),
    );
    children.add(
      PrimaryButton(label: 'Not now', onPressed: account.cancelExport),
    );
    return children;
  }

  List<Widget> _exportResult(BuildContext context, AccountController account) {
    final ExportResult? result = account.exportResult;
    final String sentence = switch (result) {
      ExportResult.saved => 'The file stays on this phone until you leave this screen. The copy is not encrypted. If the app closes first, the next launch removes it. This build does not open it or send it.',
      ExportResult.notSaved => 'The file was not prepared.',
      ExportResult.cancelled || null => 'No file was prepared.',
    };
    final bool unlockBlocksRetry =
        account.unlockGate == PhoneUnlockGate.unavailable;
    return <Widget>[
      Text(sentence),
      ..._unlockOutcome(account),
      if (result == ExportResult.notSaved && !unlockBlocksRetry)
        PrimaryButton(
          label: 'Try again',
          onPressed: () => unawaited(account.confirmExport()),
        ),
      PrimaryButton(label: 'Back', onPressed: () => _back(context, account)),
    ];
  }

  List<Widget> _deleteChildren(
    BuildContext context,
    AccountController account,
  ) {
    if (account.phase == AccountPhase.deleteResult) {
      return _deleteResult(context, account);
    }
    final List<Widget> children = <Widget>[
      const Text('Remove this profile?'),
      const Text(
        'This phone deletes the profile after you confirm. Nothing new is uploaded. Copies you already saved are not erased.',
      ),
    ];
    if (account.namesSignInRemoval) {
      children.add(const Text('This sign-in is removed with the profile.'));
    }
    if (account.unlockGate == PhoneUnlockGate.checking) {
      children.add(const Text("Checking this phone's unlock."));
      return children;
    }
    if (account.unlockGate == PhoneUnlockGate.unavailable) {
      children.add(
        const Text(
          "This phone has no unlock check, so this action is unavailable.",
        ),
      );
      children.add(
        PrimaryButton(label: 'Not now', onPressed: account.cancelDelete),
      );
      return children;
    }
    if (account.unlockGate == PhoneUnlockGate.canceled) {
      children.add(const Text('Nothing was saved or removed.'));
    } else if (account.unlockGate == PhoneUnlockGate.unfinished) {
      children.add(
        const Text(
          'The phone unlock check did not finish. Nothing was saved or removed.',
        ),
      );
    }
    if (account.confirmInFlight) {
      children.add(const Text('Removing this profile.'));
      if (!account.rpcDispatched) {
        children.add(
          PrimaryButton(label: 'Not now', onPressed: account.cancelDelete),
        );
      }
      return children;
    }
    children.add(
      PrimaryButton(
        label: 'Remove it',
        onPressed: () => unawaited(account.confirmDelete()),
      ),
    );
    children.add(
      PrimaryButton(label: 'Not now', onPressed: account.cancelDelete),
    );
    return children;
  }

  List<Widget> _deleteResult(BuildContext context, AccountController account) {
    final DeleteResult? result = account.deleteResult;
    final String sentence = switch (result) {
      DeleteResult.cancelled || null => 'This profile stays on this phone.',
      DeleteResult.stillHere => 'The profile is still on this phone.',
      DeleteResult.signInRemoved =>
        'The sign-in was removed. The profile is still on this phone.',
      DeleteResult.removed => 'This profile was removed from this phone.',
      DeleteResult.removedWithSignIn => 'This profile was removed from this phone. This sign-in was removed with it.',
      DeleteResult.notReplaced =>
        account.rpcCommitted
            ? 'The profile was removed from this phone. This sign-in was removed with it. A new profile was not opened.'
            : 'The profile was removed from this phone. A new profile was not opened.',
    };
    final bool tryAgain =
        result == DeleteResult.stillHere ||
        result == DeleteResult.signInRemoved ||
        result == DeleteResult.notReplaced;
    final bool unlockBlocksRetry =
        account.unlockGate == PhoneUnlockGate.unavailable;
    return <Widget>[
      Text(sentence),
      ..._unlockOutcome(account),
      if (tryAgain && !unlockBlocksRetry)
        PrimaryButton(
          label: 'Try again',
          onPressed: () => unawaited(_retryDelete(account)),
        ),
      PrimaryButton(label: 'Back', onPressed: () => _back(context, account)),
    ];
  }

  List<Widget> _unlockOutcome(AccountController account) {
    switch (account.unlockGate) {
      case PhoneUnlockGate.canceled:
        return const <Widget>[Text('Nothing was saved or removed.')];
      case PhoneUnlockGate.unfinished:
        return const <Widget>[
          Text(
            'The phone unlock check did not finish. Nothing was saved or removed.',
          ),
        ];
      case PhoneUnlockGate.unavailable:
        return const <Widget>[
          Text(
            "This phone has no unlock check, so this action is unavailable.",
          ),
        ];
      case PhoneUnlockGate.checking:
      case PhoneUnlockGate.ready:
        return const <Widget>[];
    }
  }

  Future<void> _retryDelete(AccountController account) {
    switch (account.deleteResult) {
      case DeleteResult.signInRemoved:
        return account.retryLocalDelete();
      case DeleteResult.notReplaced:
        return account.retryCreateProfile();
      case DeleteResult.stillHere:
        return account.confirmDelete();
      case DeleteResult.cancelled:
      case DeleteResult.removed:
      case DeleteResult.removedWithSignIn:
      case null:
        return Future<void>.value();
    }
  }

  void _back(BuildContext context, AccountController account) {
    final DeleteResult? deleting = account.deleteResult;
    final bool stay =
        deleting == DeleteResult.signInRemoved ||
        deleting == DeleteResult.removed ||
        deleting == DeleteResult.removedWithSignIn ||
        deleting == DeleteResult.notReplaced;
    account.dismissResult();
    if (!stay) {
      context.go('/focus/privacy');
    }
  }

  List<Widget> _phaseChildren(BuildContext context, AccountController account) {
    switch (account.phase) {
      case AccountPhase.signedOut:
        return <Widget>[
          const Text(
            'An account is optional. Workouts on this device stay on this device.',
          ),
          PrimaryButton(
            label: 'Stay on this device',
            onPressed: () => context.go('/'),
          ),
          if (account.actorId != null)
            PrimaryButton(
              label: 'Use this sign-in',
              onPressed: account.beginBind,
            ),
        ];
      case AccountPhase.confirmBind:
        return <Widget>[
          const Text(
            'Use this sign-in with the profile already on this device? Nothing is uploaded.',
          ),
          PrimaryButton(
            label: 'Use this sign-in',
            onPressed: () => unawaited(account.confirmBind()),
          ),
          PrimaryButton(label: 'Not now', onPressed: account.cancelBind),
        ];
      case AccountPhase.signedIn:
        return <Widget>[
          const Text('Signed in on this device.'),
          if (!account.copyAccepted)
            PrimaryButton(
              label: 'Bring this profile over',
              onPressed: account.openCopyPreview,
            ),
          PrimaryButton(label: 'Sign out', onPressed: account.requestSignOut),
        ];
      case AccountPhase.signOutChoice:
        return <Widget>[
          PrimaryButton(
            label: 'Keep a locked copy on this device',
            onPressed: () => unawaited(account.keepLocked()),
          ),
          PrimaryButton(
            label: 'Remove the copy on this device',
            onPressed: () => unawaited(account.removeLocal()),
          ),
        ];
      case AccountPhase.switching:
        return const <Widget>[Text('Opening the other profile.')];
      case AccountPhase.expired:
        return const <Widget>[
          Text('This sign-in expired. Workouts on this device stay here.'),
        ];
      case AccountPhase.accessRemoved:
        return const <Widget>[
          Text(
            'This sign-in cannot be used. Workouts on this device stay here.',
          ),
        ];
      case AccountPhase.reauth:
        return <Widget>[
          const Text('Confirm this sign-in to continue.'),
          PrimaryButton(label: 'Confirm', onPressed: account.confirmReauth),
          PrimaryButton(label: 'Cancel', onPressed: account.cancelReauth),
        ];
      case AccountPhase.exportPreview:
      case AccountPhase.exportResult:
      case AccountPhase.deletePreview:
      case AccountPhase.deleteResult:
        return const <Widget>[];
    }
  }
}

class _AccountScroll extends StatelessWidget {
  const _AccountScroll({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final List<Widget> spaced = <Widget>[];
    for (var index = 0; index < children.length; index++) {
      if (index > 0) {
        spaced.add(const SizedBox(height: AppSpacing.space24));
      }
      spaced.add(children[index]);
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.space20),
      children: spaced,
    );
  }
}
