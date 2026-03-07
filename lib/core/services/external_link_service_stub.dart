import 'package:url_launcher/url_launcher.dart';

Future<bool> openExternalLink(String url) {
  return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
}
