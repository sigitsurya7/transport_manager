import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:persistence/persistence.dart';

import '../data/game_data.dart';

final gameDataProvider = FutureProvider<GameData>((ref) => GameData.load(rootBundle));

final saveStoreProvider = FutureProvider<SaveStore>((ref) async {
  final dir = await getApplicationSupportDirectory();
  return SaveStore(Directory('${dir.path}/saves'));
});
