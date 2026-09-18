import 'package:flutter/material.dart';

/// Global navigator for notification-tap routing. Notification callbacks
/// (including background isolates) can't use a BuildContext, so they push
/// through this key. Kept in its own file to avoid import cycles between
/// `app.dart` and the notification stack.
final GlobalKey<NavigatorState> larmNavigatorKey =
    GlobalKey<NavigatorState>();
