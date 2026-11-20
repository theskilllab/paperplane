import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The current time. Tests override it so ages, expiry and rotation are fixed.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
