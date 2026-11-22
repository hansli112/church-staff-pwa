import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] out of the app, never throwing: iOS's in-app browser fails
/// on a page it cannot load (no connection), and then Safari opens it, which
/// says why. False when nothing could.
Future<bool> openLink(Uri url, {LaunchMode mode = LaunchMode.platformDefault}) async {
  try {
    if (await launchUrl(url, mode: mode)) return true;
  } on PlatformException {
    // Tried below in the browser itself.
  }
  if (mode == LaunchMode.externalApplication) return false;
  try {
    return await launchUrl(url, mode: LaunchMode.externalApplication);
  } on PlatformException {
    return false;
  }
}
