import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:helpmemove/design/app_colors.dart';
import 'package:helpmemove/design/app_spacing.dart';
import 'package:helpmemove/design/components/primary_button.dart';
import 'package:helpmemove/design/components/secondary_button.dart';
import 'package:helpmemove/design/components/tertiary_button.dart';

const String explainLocalSentence = 'This note stays on this device.';

const String explainConsentLine =
    'Send the selected area or focus to Ollama Cloud for an explanation? It does not send typed or spoken symptoms.';

const String explainPlanSentence =
    'This explanation is not a change to your plan.';

const Duration explainClientTimeout = Duration(seconds: 15);

const List<String> explainRegionIds = <String>[
  'head_neck',
  'shoulder',
  'arm',
  'torso',
  'pelvis',
  'leg',
  'foot',
];

const List<String> explainFocusIds = <String>[
  'strength',
  'mobility',
  'stability',
  'conditioning',
  'control',
];

/// Test seam. Production leaves this null and posts with [HttpClient].
typedef ExplainPoster = Future<String> Function(
  HttpClient client,
  Uri uri,
  String jsonBody,
);

class ExplainScreen extends StatefulWidget {
  const ExplainScreen({
    super.key,
    this.apiBase = const String.fromEnvironment('COACH_API_BASE'),
    this.httpClientFactory,
    this.poster,
  });

  final String apiBase;
  final HttpClient Function()? httpClientFactory;
  final ExplainPoster? poster;

  @override
  State<ExplainScreen> createState() => _ExplainScreenState();
}

class _ExplainScreenState extends State<ExplainScreen> {
  String? _kind;
  String? _id;
  var _kept = false;
  var _sending = false;
  String? _reply;
  var _generation = 0;
  HttpClient? _client;

  bool get _remote => widget.apiBase.isNotEmpty;

  bool get _showLocal => _reply == null && _kind != null && (!_remote || _kept);

  bool get _showConsent => _remote && _kind != null && !_kept && _reply == null;

  @override
  void dispose() {
    _generation += 1;
    _closeClient();
    super.dispose();
  }

  void _closeClient() {
    final HttpClient? client = _client;
    _client = null;
    if (client == null) {
      return;
    }
    try {
      client.close(force: true);
    } on Object {
      // The route already closed this client.
    }
  }

  void _choose(String kind, String id) {
    _generation += 1;
    _closeClient();
    setState(() {
      if (_kind == kind && _id == id) {
        _kind = null;
        _id = null;
      } else {
        _kind = kind;
        _id = id;
      }
      _kept = false;
      _sending = false;
      _reply = null;
    });
  }

  void _keep() {
    _generation += 1;
    _closeClient();
    setState(() {
      _kept = true;
      _sending = false;
      _reply = null;
    });
  }

  Future<void> _send() async {
    final String? kind = _kind;
    final String? id = _id;
    if (_sending || !_remote || kind == null || id == null) {
      return;
    }
    final int generation = _generation;
    setState(() {
      _sending = true;
    });
    HttpClient? client;
    try {
      final HttpClient Function() create =
          widget.httpClientFactory ?? HttpClient.new;
      final HttpClient opened = create();
      client = opened;
      opened.connectionTimeout = explainClientTimeout;
      _client = opened;
      final String jsonBody = jsonEncode(<String, String>{
        'selection_kind': kind,
        'selection_id': id,
      });
      final Uri uri = Uri.parse(
        '${_trimmedBase(widget.apiBase)}/coach/explain',
      );
      final ExplainPoster? poster = widget.poster;
      final Future<String> pending = poster == null
          ? postExplainRequest(opened, uri, jsonBody)
          : poster(opened, uri, jsonBody);
      final String raw = await pending.timeout(explainClientTimeout);
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _sending = false;
        _reply = _limitReply(raw);
      });
    } on Object {
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() {
        _sending = false;
      });
    } finally {
      final HttpClient? opened = client;
      if (opened != null) {
        if (identical(_client, opened)) {
          _client = null;
        }
        try {
          opened.close(force: true);
        } on Object {
          // Left the route while the body was still open.
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColors colors = appColorsOf(context);
    return RepaintBoundary(
      key: const Key('explain-capture'),
      child: Scaffold(
        backgroundColor: colors.surface,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Explain a selection'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.space20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TertiaryButton(
                    label: 'Back',
                    onPressed: () => context.go('/foundations'),
                  ),
                ),
                if (_reply != null) ...<Widget>[
                  const SizedBox(height: AppSpacing.space16),
                  Text(_reply!, key: const Key('explain-reply')),
                  const SizedBox(height: AppSpacing.space12),
                  const Text(explainPlanSentence),
                ],
                if (_showLocal) ...<Widget>[
                  const SizedBox(height: AppSpacing.space16),
                  const Text(explainLocalSentence),
                ],
                if (_showConsent) ...<Widget>[
                  const SizedBox(height: AppSpacing.space16),
                  const Text(explainConsentLine),
                  const SizedBox(height: AppSpacing.space16),
                  PrimaryButton(
                    label: 'Send',
                    loading: _sending,
                    onPressed: _sending ? null : () => unawaited(_send()),
                  ),
                  const SizedBox(height: AppSpacing.space12),
                  SecondaryButton(
                    label: 'Keep it on this device',
                    onPressed: _keep,
                  ),
                ],
                const SizedBox(height: AppSpacing.space24),
                Text('Area', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.space12),
                Wrap(
                  spacing: AppSpacing.space8,
                  runSpacing: AppSpacing.space8,
                  children: [
                    for (final String id in explainRegionIds)
                      _option('region', id),
                  ],
                ),
                const SizedBox(height: AppSpacing.space24),
                Text('Focus', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.space12),
                Wrap(
                  spacing: AppSpacing.space8,
                  runSpacing: AppSpacing.space8,
                  children: [
                    for (final String id in explainFocusIds)
                      _option('focus', id),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _option(String kind, String id) {
    final bool selected = _kind == kind && _id == id;
    final String label = _label(id);
    final Widget button = selected
        ? PrimaryButton(label: label, onPressed: () => _choose(kind, id))
        : SecondaryButton(label: label, onPressed: () => _choose(kind, id));
    return Semantics(selected: selected, child: button);
  }
}

String _trimmedBase(String base) {
  if (base.endsWith('/')) {
    return base.substring(0, base.length - 1);
  }
  return base;
}

String _label(String token) {
  if (token == 'head_neck') {
    return 'Head and neck';
  }
  final String spaced = token.replaceAll('_', ' ');
  return spaced[0].toUpperCase() + spaced.substring(1);
}

String _limitReply(String value) {
  final List<int> scalars = value.runes.toList();
  if (scalars.length <= 500) {
    return value;
  }
  return String.fromCharCodes(scalars.take(500));
}

Future<String> postExplainRequest(
  HttpClient client,
  Uri uri,
  String jsonBody,
) async {
  final HttpClientRequest request = await client.postUrl(uri);
  request.headers.contentType = ContentType(
    'application',
    'json',
    charset: 'utf-8',
  );
  request.add(utf8.encode(jsonBody));
  final HttpClientResponse response = await request.close();
  return response.transform(utf8.decoder).join();
}
