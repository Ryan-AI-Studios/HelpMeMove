import 'package:flutter/material.dart';

import 'package:helpmemove/design/app_spacing.dart';
import 'package:helpmemove/design/components/app_card.dart';
import 'package:helpmemove/design/components/primary_button.dart';

class StorageFailureScreen extends StatelessWidget {
  const StorageFailureScreen({super.key, required this.onRetry});

  final VoidCallback? onRetry;

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
                      'Storage is unavailable',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: AppSpacing.space12),
                    const Text(
                      'HelpMeMove could not open local storage on this device. Nothing was saved.',
                    ),
                    const SizedBox(height: AppSpacing.space20),
                    PrimaryButton(label: 'Retry', onPressed: onRetry),
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
