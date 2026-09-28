import 'package:flutter/material.dart';

/// Global navigator key.
///
/// Used by Firebase messaging handlers (and any other code outside the
/// widget tree) to push routes without needing a BuildContext.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// A pending notification tap that could not be handled immediately
/// because the user wasn't signed in yet. Consumed by the auth listener
/// in main.dart once a session becomes available.
Map<String, dynamic>? pendingNotificationTap;