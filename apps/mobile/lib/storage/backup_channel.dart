import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const MethodChannel storageBackupChannel = MethodChannel('helpmemove/storage');

/// Asks iOS to set `NSURLIsExcludedFromBackupKey` on the profile directory.
Future<void> excludeFromBackupOnIos(String path) async {
  if (kIsWeb || !Platform.isIOS) {
    return;
  }
  await storageBackupChannel.invokeMethod<void>('excludeFromBackup', path);
}
