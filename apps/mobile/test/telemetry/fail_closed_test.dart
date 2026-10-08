import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const List<String> _sdkTokens = <String>[
  'posthog',
  'posthog_flutter',
  'sentry',
  'sentry_flutter',
  'amplitude',
  'mixpanel',
  'firebase_analytics',
  'firebase_crashlytics',
];

const List<String> _libTokens = <String>[
  ..._sdkTokens,
  'package:http/',
  'package:dio/',
  'PosthogObserver',
  'SentryNavigatorObserver',
  'SentryWidget',
  'sessionReplay',
  'captureApplicationLifecycleEvents',
];

const List<String> _gateForbidden = <String>[
  'accepted',
  'asName',
  'http',
  'HttpClient',
  'Uri.https',
  'WebSocket',
  'InternetAddress',
];

const List<String> _crateTokens = <String>[
  'sentry',
  'sentry-tracing',
  'opentelemetry',
];

const List<String> _manifestTokens = <String>[
  'posthog',
  'sentry',
  'com.posthog',
  'SENTRY_DSN',
];

void main() {
  test('pubspec stays free of analytics and crash SDKs', () {
    for (final String path in <String>['pubspec.yaml', 'pubspec.lock']) {
      final String content = File(path).readAsStringSync();
      for (final String token in _sdkTokens) {
        expect(content.contains(token), isFalse, reason: '$path $token');
      }
    }
  });

  test('library sources stay free of analytics and crash SDKs', () {
    for (final File file in _dartFiles(Directory('lib'))) {
      final String content = file.readAsStringSync();
      for (final String token in _libTokens) {
        expect(content.contains(token), isFalse, reason: '${file.path} $token');
      }
    }
  });

  test('product event gate stays rejected and offline', () {
    final String content = File('lib/telemetry/product_event.dart')
        .readAsStringSync();
    expect(content.contains('ProductEventDecision.rejected'), isTrue);
    for (final String token in _gateForbidden) {
      expect(content.contains(token), isFalse, reason: token);
    }
  });

  test('no other library file names the product event gate', () {
    for (final File file in _dartFiles(Directory('lib'))) {
      if (_isGateFile(file.path)) {
        continue;
      }
      expect(
        file.readAsStringSync().contains('product_event.dart'),
        isFalse,
        reason: file.path,
      );
    }
  });

  test('profile database keeps schema 10 and the storage probe', () {
    final String content = File('lib/storage/profile_database.dart')
        .readAsStringSync();
    expect(content.contains('schemaVersion => 10'), isTrue);
    expect(content.contains("CHECK (event_type = 'storage-probe')"), isTrue);
    expect(
      content.contains("CHECK (payload_text = 'helpmemove-storage-probe')"),
      isTrue,
    );
  });

  test('workspace crates stay free of tracing exporters', () {
    final List<File> manifests = <File>[
      File('../../Cargo.toml'),
      ...Directory('../../crates')
          .listSync()
          .whereType<Directory>()
          .map((Directory crate) => File('${crate.path}/Cargo.toml'))
          .where((File file) => file.existsSync()),
    ];
    expect(manifests, isNotEmpty);
    for (final File file in manifests) {
      final String content = file.readAsStringSync();
      for (final String token in _crateTokens) {
        expect(content.contains(token), isFalse, reason: '${file.path} $token');
      }
    }
  });

  test('native manifests stay free of analytics and crash tokens', () {
    for (final String path in <String>[
      'android/app/src/main/AndroidManifest.xml',
      'ios/Runner/Info.plist',
    ]) {
      final String content = File(path).readAsStringSync();
      for (final String token in _manifestTokens) {
        expect(content.contains(token), isFalse, reason: '$path $token');
      }
    }
  });
}

bool _isGateFile(String path) {
  return path
      .replaceAll('\\', '/')
      .endsWith('lib/telemetry/product_event.dart');
}

Iterable<File> _dartFiles(Directory directory) {
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((File file) => file.path.endsWith('.dart'));
}
