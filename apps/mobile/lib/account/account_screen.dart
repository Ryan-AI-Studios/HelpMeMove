import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/account/account_controller.dart';
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

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, this.controller, this.unavailable = false});

  final AccountController? controller;
  final bool unavailable;

  @override
  Widget build(BuildContext context) {
    final AccountController? account = controller;
    return RepaintBoundary(
      key: const Key('account-capture'),
      child: Scaffold(
        body: SafeArea(
          child: unavailable || account == null
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
    );
  }

  List<Widget> _children(BuildContext context, AccountController account) {
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
