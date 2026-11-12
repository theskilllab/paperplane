import 'dart:io';

/// A short device label for the board-key name, for example `iPhone`.
///
/// `Platform.localHostname` is the closest the app can get without a new
/// dependency. It may be a person's name on a desktop, so it is only sent to
/// the user's own server, never logged, and truncated.
String platformDeviceName() {
  try {
    final host = Platform.localHostname.trim();
    if (host.isNotEmpty) return _clean(host);
  } on Object {
    // Fall through to the operating system name.
  }
  return switch (Platform.operatingSystem) {
    'ios' => 'iPhone',
    'android' => 'Android',
    'macos' => 'Mac',
    _ => 'Device',
  };
}

/// The board-key name the app asks for: `Paperplane (<device>)`.
String keyNameForDevice(String device) => 'Paperplane (${_clean(device)})';

String _clean(String value) {
  final cleaned = value
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
  if (cleaned.isEmpty) return 'Device';
  return cleaned.length <= 48 ? cleaned : cleaned.substring(0, 48);
}
