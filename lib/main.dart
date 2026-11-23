import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'data/api.dart';
import 'router.dart';
import 'theme.dart';
import 'widgets/web_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  await apiClient.restoreSession();
  runApp(EvShareGridApp());
}

class EvShareGridApp extends StatelessWidget {
  EvShareGridApp({super.key, String? initialLocation, ApiClient? api})
    : _client = api ?? apiClient,
      _router = buildRouter(initialLocation: initialLocation, api: api);

  final ApiClient _client;
  final GoRouter _router;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'EV ShareGrid',
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    builder: (context, child) => PortalSession(client: _client, child: child!),
    routerConfig: _router,
  );
}
