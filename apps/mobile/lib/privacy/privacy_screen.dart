import 'dart:async';

import 'package:drift/isolate.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sqlite3/sqlite3.dart' hide Row;
import 'package:helpmemove/design/app_spacing.dart';
import 'package:helpmemove/design/components/primary_button.dart';
import 'package:helpmemove/storage/profile_store.dart';
import 'package:helpmemove/storage/storage_exception.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key, required this.store, this.onAppearanceSaved});

  final ProfileStore store;
  final void Function(String choice)? onAppearanceSaved;

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  var _ready = false;
  var _unreadable = false;
  var _storageFailed = false;
  var _saving = false;
  String? _choice;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final String? stored = await widget.store.loadAppearanceChoice();
      if (!mounted) {
        return;
      }
      if (stored == null ||
          stored == 'system' ||
          stored == 'light' ||
          stored == 'dark') {
        setState(() {
          _ready = true;
          _unreadable = false;
          _choice = stored ?? 'system';
        });
        return;
      }
      setState(() {
        _ready = true;
        _unreadable = true;
        _choice = null;
      });
    } on StorageKeyLoss {
      _failStorage();
    } on StorageCipherUnavailable {
      _failStorage();
    } on StorageSchemaException {
      _failStorage();
    } on StorageIoException {
      _failStorage();
    } on SqliteException {
      _failStorage();
    } on DriftRemoteException {
      _failStorage();
    }
  }

  Future<void> _select(String choice) async {
    if (_saving || _storageFailed || _unreadable) {
      return;
    }
    _saving = true;
    try {
      await widget.store.saveAppearanceChoice(choice);
      widget.onAppearanceSaved?.call(choice);
      if (!mounted) {
        return;
      }
      setState(() {
        _choice = choice;
      });
    } on StorageKeyLoss {
      _failStorage();
    } on StorageCipherUnavailable {
      _failStorage();
    } on StorageSchemaException {
      _failStorage();
    } on StorageIoException {
      _failStorage();
    } on SqliteException {
      _failStorage();
    } on DriftRemoteException {
      _failStorage();
    } finally {
      _saving = false;
    }
  }

  void _failStorage() {
    if (!mounted) {
      return;
    }
    setState(() {
      _ready = true;
      _storageFailed = true;
      _unreadable = false;
      _choice = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.go('/storage-failure');
    });
  }

  Widget _choiceRow(String token, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<String>(value: token),
        GestureDetector(
          onTap: () {
            unawaited(_select(token));
          },
          child: Text(label),
        ),
      ],
    );
  }

  Widget _readyBody() {
    if (_unreadable) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('The saved appearance could not be read.'),
          const SizedBox(height: AppSpacing.space24),
          PrimaryButton(label: 'Back', onPressed: () => context.go('/')),
        ],
      );
    }
    final String choice = _choice ?? 'system';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Privacy and appearance'),
        const SizedBox(height: AppSpacing.space24),
        const Text('This profile stays on this device.'),
        const SizedBox(height: AppSpacing.space24),
        const Text('The profile database is encrypted.'),
        const SizedBox(height: AppSpacing.space24),
        const Text('Cloud sync is not connected.'),
        const SizedBox(height: AppSpacing.space24),
        const Text('No AI coach is active.'),
        const SizedBox(height: AppSpacing.space24),
        const Text('Appearance'),
        const SizedBox(height: AppSpacing.space24),
        RadioGroup<String>(
          groupValue: choice,
          onChanged: (String? value) {
            if (value == null) {
              return;
            }
            unawaited(_select(value));
          },
          child: Column(
            children: [
              _choiceRow('system', 'System'),
              _choiceRow('light', 'Light'),
              _choiceRow('dark', 'Dark'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.space24),
        PrimaryButton(label: 'Back', onPressed: () => context.go('/')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space20),
          child: _ready
              ? LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: constraints.maxWidth,
                          minHeight: constraints.maxHeight,
                        ),
                        child: _storageFailed
                            ? const SizedBox.shrink()
                            : _readyBody(),
                      ),
                    );
                  },
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
