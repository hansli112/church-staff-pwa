import 'package:web/web.dart' as web;

Future<bool> openExternalLink(String url) async {
  web.window.open(url, '_blank');
  return true;
}
