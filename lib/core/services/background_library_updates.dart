import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../notifications/notification_service.dart';
import '../parser/parser_registry.dart';
import 'library_update_service.dart';

const libraryUpdateTask = 'com.panovault.library.chapter_updates';
const libraryUpdateFrequency = Duration(minutes: 30);
const libraryUpdateBudget = Duration(seconds: 20);

@pragma('vm:entry-point')
void callbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  Workmanager().executeTask((task, inputData) => dispatchLibraryUpdate(task));
}

/// Injectable boundaries let tests exercise dispatch without starting native engines.
Future<bool> dispatchLibraryUpdate(
  String task, {
  Future<void> Function()? initialize,
  Future<void> Function()? check,
}) async {
  if (task != libraryUpdateTask) return false;
  try {
    await (initialize ??
            () async {
              await ParserRegistry.instance.loadCustomSources(strict: true);
              // Initialization never requests permissions; only foreground main does.
              await NotificationService.instance.init();
            })()
        .timeout(const Duration(seconds: 5));
    await (check ??
        () async {
          await LibraryUpdateService.instance.checkForUpdates(
            budget: libraryUpdateBudget,
          );
        })();
    return true;
  } catch (error, stack) {
    debugPrint('Background chapter updates failed: $error\n$stack');
    return false;
  }
}

Future<void> registerBackgroundLibraryUpdates({
  Workmanager? scheduler,
  TargetPlatform? platform,
}) async {
  final target = platform ?? defaultTargetPlatform;
  if (kIsWeb ||
      (target != TargetPlatform.android && target != TargetPlatform.iOS)) {
    return;
  }
  final manager = scheduler ?? Workmanager();
  await manager.initialize(callbackDispatcher);
  await manager.registerPeriodicTask(
    libraryUpdateTask,
    libraryUpdateTask,
    frequency: libraryUpdateFrequency,
    initialDelay: libraryUpdateFrequency,
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
  );
}
