import 'package:flutter/services.dart';
import 'dart:async';

class ClipboardService {
  static const MethodChannel _channel = MethodChannel('key_core/clipboard');

  Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<String?> getFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }

  Future<void> copyWithAutoClear(String text, {int delaySeconds = 30}) async {
    await copyToClipboard(text);
    Timer(Duration(seconds: delaySeconds), () async {
      await clearClipboard();
    });
  }

  Future<void> clearClipboard() async {
    try {
      await Clipboard.setData(const ClipboardData(text: ''));
    } catch (e) {
    }
  }
}
