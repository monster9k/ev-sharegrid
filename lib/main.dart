import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'data/api.dart';
import 'router.dart';
import 'theme.dart';

void main() {
  usePathUrlStrategy();
  runApp(EvShareGridApp());
}

class EvShareGridApp extends StatelessWidget {
  EvShareGridApp({super.key, String? initialLocation, ApiClient? api})
    : _router = buildRouter(initialLocation: initialLocation, api: api);

  final GoRouter _router;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'EV ShareGrid',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    routerConfig: _router,
  );
}
