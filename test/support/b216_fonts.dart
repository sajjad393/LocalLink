import 'dart:io';

import 'package:flutter/services.dart';

bool _loaded = false;

/// Bundle 216: load the real Roboto216 font so text sizes match the phone.
Future<void> loadRoboto216() async {
  if (_loaded) return;
  final loader = FontLoader('Roboto216');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    final bytes = File('assets/fonts/Roboto-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(Uint8List.fromList(bytes))));
  }
  await loader.load();
  _loaded = true;
}
