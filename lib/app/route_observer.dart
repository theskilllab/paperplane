import 'package:flutter/widgets.dart';

/// Tells screens when another screen covers them or is closed again.
///
/// Only full pages count, not sheets: the Inbox uses it to stop polling while
/// a detail screen is on top. Registered in the router's `observers`.
final RouteObserver<PageRoute<void>> appRouteObserver =
    RouteObserver<PageRoute<void>>();
