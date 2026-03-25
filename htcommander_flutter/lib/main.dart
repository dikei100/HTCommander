import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'app_init.dart';
import 'core/data_broker.dart';
import 'core/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize settings persistence
  final store = await SharedPrefsSettingsStore.create();
  DataBroker.initialize(store);

  // Register all data handlers
  initializeDataHandlers();

  // Initialize handler file persistence paths
  final String appDataPath;
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'] ?? '.';
    appDataPath = '$appData\\HTCommander';
  } else if (Platform.isAndroid) {
    final dir = await getApplicationDocumentsDirectory();
    appDataPath = dir.path;
  } else {
    final home = Platform.environment['HOME'] ?? '.';
    appDataPath = '$home/.local/share/HTCommander';
  }
  initializeHandlerPaths(appDataPath);

  // Log startup
  DataBroker.dispatch(1, 'LogInfo', 'HTCommander-X Flutter started', store: false);

  runApp(const HTCommanderApp());
}
