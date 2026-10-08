import 'dart:async';

import 'package:flutter/material.dart';

import 'package:helpmemove/design/app_spacing.dart';
import 'package:helpmemove/design/components/app_card.dart';
import 'package:helpmemove/design/components/destructive_button.dart';
import 'package:helpmemove/design/components/primary_button.dart';
import 'package:helpmemove/design/components/tertiary_button.dart';

class KeyLossScreen extends StatelessWidget {
  const KeyLossScreen({
    super.key,
    required this.onRetry,
    required this.onReset,
  });

  final VoidCallback? onRetry;
  final VoidCallback? onReset;

  Future<void> _confirmReset(BuildContext context) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return RepaintBoundary(
          key: const Key('storage-confirm-capture'),
          child: AlertDialog(
            title: const Text('Delete local data?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'This deletes the local data stored on this device. It cannot be undone.',
                ),
                const SizedBox(height: AppSpacing.space16),
                TertiaryButton(
                  label: 'Cancel',
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                ),
                const SizedBox(height: AppSpacing.space8),
                DestructiveButton(
                  label: 'Delete local data',
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (confirmed == true) {
      onReset?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: const Key('storage-capture'),
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.space20),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Local data cannot be opened',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.space12),
                    const Text(
                      'The key for local data on this device is missing. HelpMeMove cannot recover it. You can retry, or delete the local data on this device and start again.',
                    ),
                    const SizedBox(height: AppSpacing.space20),
                    PrimaryButton(label: 'Retry', onPressed: onRetry),
                    const SizedBox(height: AppSpacing.space12),
                    DestructiveButton(
                      label: 'Reset local data',
                      onPressed: onReset == null
                          ? null
                          : () {
                              unawaited(_confirmReset(context));
                            },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
