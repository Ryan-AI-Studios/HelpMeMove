import 'dart:async';

import 'package:flutter/material.dart';
import 'package:helpmemove/design/app_colors.dart';
import 'package:helpmemove/design/app_radius.dart';
import 'package:helpmemove/design/app_spacing.dart';
import 'package:helpmemove/design/components/primary_button.dart';
import 'package:helpmemove/design/components/secondary_button.dart';

/// Result of asking the device for a positioning preview.
sealed class CameraOpenResult {
  const CameraOpenResult();
}

class CameraOpened extends CameraOpenResult {
  const CameraOpened(this.preview);

  final Widget preview;
}

class CameraOpenUnavailable extends CameraOpenResult {
  const CameraOpenUnavailable();
}

/// Opens and closes a preview. The guidance widget does not import the camera plugin.
abstract class CameraPreviewHost {
  Future<CameraOpenResult> open();

  Future<void> close();
}

/// Permission, local preview, or an unavailable state, then the manual workout.
class CameraGuidance extends StatefulWidget {
  const CameraGuidance({super.key, required this.host, required this.onLeave});

  final CameraPreviewHost host;
  final VoidCallback onLeave;

  @override
  State<CameraGuidance> createState() => _CameraGuidanceState();
}

enum _Stage { permission, preview, unavailable }

class _CameraGuidanceState extends State<CameraGuidance>
    with WidgetsBindingObserver {
  _Stage _stage = _Stage.permission;
  Widget? _preview;
  bool _busy = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.host.close());
    super.dispose();
  }

  @override
  void didUpdateWidget(CameraGuidance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.host, widget.host)) {
      return;
    }
    _generation += 1;
    _stage = _Stage.permission;
    _preview = null;
    _busy = false;
    unawaited(oldWidget.host.close());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      unawaited(_returnToPermission());
    }
  }

  Future<void> _returnToPermission() async {
    _generation += 1;
    await widget.host.close();
    if (!mounted) {
      return;
    }
    setState(() {
      _stage = _Stage.permission;
      _preview = null;
      _busy = false;
    });
  }

  Future<void> _leave() async {
    _generation += 1;
    await widget.host.close();
    if (!mounted) {
      return;
    }
    widget.onLeave();
  }

  Future<void> _enable() async {
    if (_busy) {
      return;
    }
    final int generation = ++_generation;
    setState(() => _busy = true);
    final CameraOpenResult result = await widget.host.open();
    if (!mounted || generation != _generation) {
      return;
    }
    setState(() {
      _busy = false;
      if (result is CameraOpened) {
        _stage = _Stage.preview;
        _preview = result.preview;
      } else {
        _stage = _Stage.unavailable;
        _preview = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = appColorsOf(context);
    final TextTheme text = Theme.of(context).textTheme;
    final String title = switch (_stage) {
      _Stage.permission => 'Use your camera for a positioning preview?',
      _Stage.preview => 'Position your phone',
      _Stage.unavailable => 'Camera unavailable',
    };
    final String body = switch (_stage) {
      _Stage.permission => 'The preview stays on this device and is not saved. It does not measure a joint or count a rep.',
      _Stage.preview => 'Step back until your whole body fits in the guide.',
      _Stage.unavailable => 'You can continue the workout without the camera.',
    };
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.space20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(title, style: text.headlineSmall),
                      const SizedBox(height: AppSpacing.space16),
                      Text(body, style: text.bodyLarge),
                      if (_stage == _Stage.permission) ...[
                        const SizedBox(height: AppSpacing.space16),
                        Text(
                          'Keep other people, especially children, out of the view.',
                          style: text.bodyLarge,
                        ),
                      ],
                      if (_stage == _Stage.preview && _preview != null) ...[
                        const SizedBox(height: AppSpacing.space16),
                        AspectRatio(
                          aspectRatio: 3 / 4,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.all(
                              Radius.circular(AppRadius.large),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                _preview!,
                                IgnorePointer(
                                  child: Center(
                                    child: FractionallySizedBox(
                                      widthFactor: 0.62,
                                      heightFactor: 0.78,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: colors.accent,
                                            width: 2,
                                          ),
                                          borderRadius: const BorderRadius.all(
                                            Radius.circular(AppRadius.large),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.space24),
                      ..._actions(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _actions() {
    return switch (_stage) {
      _Stage.permission => [
        PrimaryButton(
          label: 'Enable camera',
          loading: _busy,
          onPressed: _busy ? null : () => unawaited(_enable()),
        ),
        const SizedBox(height: AppSpacing.space12),
        SecondaryButton(label: 'Not now', onPressed: () => unawaited(_leave())),
      ],
      _Stage.preview => [
        PrimaryButton(label: 'Continue', onPressed: () => unawaited(_leave())),
        const SizedBox(height: AppSpacing.space12),
        SecondaryButton(
          label: 'Continue without camera',
          onPressed: () => unawaited(_leave()),
        ),
      ],
      _Stage.unavailable => [
        PrimaryButton(
          label: 'Continue without camera',
          onPressed: () => unawaited(_leave()),
        ),
      ],
    };
  }
}
