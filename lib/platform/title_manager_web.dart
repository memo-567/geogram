// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util' as js_util;
import 'title_manager_interface.dart';

final TitleManager titleManager = WebTitleManager();

class WebTitleManager implements TitleManager {
  @override
  Future<String> getTitle() async {
    return html.document.title;
  }

  @override
  Future<void> setTitle(String title) async {
    html.document.title = title;
  }

  @override
  Future<bool> isFocused() async {
    try {
      final focused = js_util.callMethod(html.document, 'hasFocus', []);
      if (focused is bool) {
        return focused;
      }
    } catch (_) {}

    try {
      final hidden = js_util.getProperty(html.document, 'hidden');
      if (hidden is bool) {
        return !hidden;
      }
    } catch (_) {}

    return true;
  }
}
