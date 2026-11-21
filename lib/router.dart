import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'data/api.dart';
import 'screens/user/onboarding_screen.dart';
import 'screens/user/login_screen.dart';
import 'screens/user/home_screen.dart';
import 'screens/user/garage_screen.dart';
import 'screens/user/map_screen.dart';
import 'screens/user/station_detail_screen.dart';
import 'screens/user/booking_screen.dart';
import 'screens/user/schedule_result_screen.dart';
import 'screens/user/sessions_screen.dart';
import 'screens/user/notifications_screen.dart';
import 'screens/user/profile_screen.dart';
import 'screens/host/host_stations_screen.dart';
import 'screens/host/host_ports_screen.dart';
import 'screens/host/host_schedule_screen.dart';
import 'screens/admin/admin_clusters_screen.dart';
import 'screens/admin/admin_review_screen.dart';
import 'screens/admin/admin_tariff_screen.dart';
import 'screens/admin/admin_solver_screen.dart';
import 'screens/admin/admin_benchmark_screen.dart';
import 'screens/admin/admin_forecast_screen.dart';
import 'widgets/mobile_frame.dart';

GoRoute _page(String path, Widget Function() build) => GoRoute(
  path: path,
  pageBuilder: (context, state) =>
      NoTransitionPage(key: state.pageKey, child: build()),
);

/// Route app USER (bọc trong khung điện thoại khi mở trên màn rộng).
List<RouteBase> _userRoutes(ApiClient client) => [
  _page('/', () => const OnboardingScreen(step: 1)),
  _page('/onboarding/2', () => const OnboardingScreen(step: 2)),
  _page('/onboarding/3', () => const OnboardingScreen(step: 3)),
  _page('/login', () => LoginScreen(client: client)),
  _page('/home', () => HomeScreen(client: client)),
  _page('/garage', () => GarageScreen(client: client)),
  _page('/map', () => MapScreen(client: client)),
  GoRoute(path: '/station', redirect: (_, _) => '/map'),
  GoRoute(
    path: '/station/:id',
    pageBuilder: (context, state) => NoTransitionPage(
      key: state.pageKey,
      child: StationDetailScreen(
        key: ValueKey(state.uri.path),
        stationId: int.tryParse(state.pathParameters['id'] ?? ''),
        client: client,
      ),
    ),
  ),
  GoRoute(
    path: '/booking',
    pageBuilder: (context, state) => NoTransitionPage(
      key: state.pageKey,
      child: BookingScreen(
        key: ValueKey(state.uri.toString()),
        stationId: int.tryParse(state.uri.queryParameters['stationId'] ?? ''),
        client: client,
      ),
    ),
  ),
  GoRoute(
    path: '/schedule',
    pageBuilder: (context, state) => NoTransitionPage(
      key: state.pageKey,
      child: ScheduleResultScreen(
        key: ValueKey(state.uri.toString()),
        client: client,
        requestId: int.tryParse(state.uri.queryParameters['requestId'] ?? ''),
        bookingResult: state.extra is Map<String, dynamic>
            ? state.extra as Map<String, dynamic>
            : null,
      ),
    ),
  ),
  _page('/sessions', () => SessionsScreen(client: client)),
  _page('/notifications', () => NotificationsScreen(client: client)),
  _page('/profile', () => ProfileScreen(client: client)),
];

/// Route web HOST và ADMIN.
List<RouteBase> _webRoutes(ApiClient client) => [
  GoRoute(path: '/host', redirect: (_, _) => '/host/stations'),
  _page('/host/stations', () => HostStationsScreen(client: client)),
  GoRoute(
    path: '/host/ports',
    pageBuilder: (context, state) => NoTransitionPage(
      key: state.pageKey,
      child: HostPortsScreen(
        key: ValueKey(state.uri.toString()),
        stationId: int.tryParse(state.uri.queryParameters['stationId'] ?? ''),
        client: client,
      ),
    ),
  ),
  GoRoute(
    path: '/host/schedule',
    pageBuilder: (context, state) => NoTransitionPage(
      key: state.pageKey,
      child: HostScheduleScreen(
        key: ValueKey(state.uri.toString()),
        stationId: int.tryParse(state.uri.queryParameters['stationId'] ?? ''),
        client: client,
      ),
    ),
  ),
  GoRoute(path: '/admin', redirect: (_, _) => '/admin/clusters'),
  _page('/admin/clusters', () => const AdminClustersScreen()),
  _page('/admin/review', () => const AdminReviewScreen()),
  _page('/admin/tariff', () => const AdminTariffScreen()),
  _page('/admin/solver', () => const AdminSolverScreen()),
  _page('/admin/benchmark', () => const AdminBenchmarkScreen()),
  _page('/admin/forecast', () => const AdminForecastScreen()),
];

GoRouter buildRouter({String? initialLocation, ApiClient? api}) {
  final client = api ?? apiClient;
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: client,
    redirect: (context, state) {
      final path = state.uri.path;
      final role = path == '/host' || path.startsWith('/host/')
          ? 'HOST'
          : path == '/admin' || path.startsWith('/admin/')
          ? 'ADMIN'
          : null;
      if (role != null && (client.accessToken == null || client.role != role)) {
        return '/login';
      }
      return null;
    },
    routes: [
      ShellRoute(
        builder: (context, state, child) => MobileFrame(child: child),
        routes: _userRoutes(client),
      ),
      ..._webRoutes(client),
    ],
  );
}
