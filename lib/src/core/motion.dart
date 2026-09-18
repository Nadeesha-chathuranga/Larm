import 'package:flutter/widgets.dart';

/// Animation duration honoring the system reduce-motion setting.
/// Returns [Duration.zero] when the user enabled "Remove animations".
Duration animDuration(BuildContext context, int millis) =>
    MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: millis);

/// Whether frame-driven motion (tickers, pulses) should run.
bool motionEnabled(BuildContext context) =>
    !MediaQuery.disableAnimationsOf(context);
