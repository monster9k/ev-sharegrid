import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'router.dart';
import 'theme.dart';

void main() => runApp(EvShareGridApp());

class EvShareGridApp extends StatelessWidget {
  EvShareGridApp({super.key, String initialLocation = '/'})
    : _router = buildRouter(initialLocation: initialLocation);

  final GoRouter _router;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'EV ShareGrid',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    routerConfig: _router,
  );
}
