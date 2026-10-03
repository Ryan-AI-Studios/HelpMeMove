import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/design/app_spacing.dart';
import 'package:helpmemove/design/components/primary_button.dart';

class FocusedFlowScreen extends StatelessWidget {
  const FocusedFlowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Focused flow')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space20),
          child: Center(
            child: PrimaryButton(
              label: 'Back',
              onPressed: () => context.go('/'),
            ),
          ),
        ),
      ),
    );
  }
}
