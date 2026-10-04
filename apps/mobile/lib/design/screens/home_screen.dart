import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/design/app_colors.dart';
import 'package:helpmemove/design/app_spacing.dart';
import 'package:helpmemove/design/components/primary_button.dart';
import 'package:helpmemove/design/components/tertiary_button.dart';
import 'package:helpmemove/src/rust/api/bridge.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  var _scaffoldCompleted = false;
  String? _bridgeResult;

  void _runBridgeCheck() {
    try {
      final String subject = acceptSubject(raw: 'subject-smoke-1');
      setState(() {
        _bridgeResult = subject == 'subject-smoke-1'
            ? 'Bridge check completed'
            : 'Bridge check failed';
      });
    } on BridgeError {
      setState(() {
        _bridgeResult = 'Bridge check failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final String? bridgeResult = _bridgeResult;
    final AppColors colors = appColorsOf(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.divider)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space8,
                  vertical: AppSpacing.space4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.space8,
                        vertical: AppSpacing.space8,
                      ),
                      child: Text('HelpMeMove'),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TertiaryButton(
                        label: 'Foundations',
                        onPressed: () => context.go('/foundations'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.space20),
                child: CustomScrollView(
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          PrimaryButton(
                            label: 'Scaffold check',
                            onPressed: () {
                              setState(() {
                                _scaffoldCompleted = true;
                              });
                            },
                          ),
                          if (_scaffoldCompleted) ...[
                            const SizedBox(height: AppSpacing.space24),
                            const Text(
                              'Scaffold check completed',
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.space24),
                          PrimaryButton(
                            label: 'Bridge check',
                            onPressed: _runBridgeCheck,
                          ),
                          if (bridgeResult != null) ...[
                            const SizedBox(height: AppSpacing.space24),
                            Text(bridgeResult, textAlign: TextAlign.center),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
