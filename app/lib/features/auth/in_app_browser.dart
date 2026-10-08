/// The app whose built-in browser [userAgent] is: Google's sign-in policy
/// turns such browsers away (403 disallowed_useragent), and on an iPhone
/// they cannot add the page to the home screen. Null for a browser of its
/// own.
String? inAppBrowser(String userAgent) {
  if (RegExp(r'\bLine/').hasMatch(userAgent)) return 'LINE';
  if (RegExp(r'FBAN|FBAV|FB_IAB').hasMatch(userAgent)) return 'Facebook';
  if (RegExp(r'\bInstagram\b').hasMatch(userAgent)) return 'Instagram';
  return null;
}
