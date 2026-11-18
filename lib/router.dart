import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
import 'theme.dart';
import 'widgets/mobile_frame.dart';

/// Màn tạm cho route chưa dựng.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen(this.name, {super.key});
  final String name;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: Text(name, style: AppFonts.display(size: 20))),
  );
}

GoRoute _page(String path, Widget Function() build) => GoRoute(
  path: path,
  pageBuilder: (context, state) =>
      NoTransitionPage(key: state.pageKey, child: build()),
);

/// Route app USER (bọc trong khung điện thoại khi mở trên màn rộng).
final _userRoutes = <RouteBase>[
  _page('/', () => const OnboardingScreen(step: 1)),
  _page('/onboarding/2', () => const OnboardingScreen(step: 2)),
  _page('/onboarding/3', () => const OnboardingScreen(step: 3)),
  _page('/login', () => const LoginScreen()),
  _page('/home', () => const HomeScreen()),
  _page('/garage', () => const GarageScreen()),
  _page('/map', () => const MapScreen()),
  _page('/station', () => const StationDetailScreen()),
  _page('/booking', () => const BookingScreen()),
  _page('/schedule', () => const ScheduleResultScreen()),
  _page('/sessions', () => const SessionsScreen()),
  _page('/notifications', () => const NotificationsScreen()),
  _page('/profile', () => const ProfileScreen()),
];

/// Route web HOST và ADMIN.
final _webRoutes = <RouteBase>[
  GoRoute(path: '/host', redirect: (_, _) => '/host/stations'),
  _page('/host/stations', () => const HostStationsScreen()),
  _page('/host/ports', () => const HostPortsScreen()),
  _page('/host/schedule', () => const HostScheduleScreen()),
  GoRoute(path: '/admin', redirect: (_, _) => '/admin/clusters'),
  _page('/admin/clusters', () => const AdminClustersScreen()),
  _page('/admin/review', () => const AdminReviewScreen()),
  _page('/admin/tariff', () => const AdminTariffScreen()),
  _page('/admin/solver', () => const AdminSolverScreen()),
  _page('/admin/benchmark', () => const AdminBenchmarkScreen()),
  _page('/admin/forecast', () => const AdminForecastScreen()),
];

GoRouter buildRouter({String? initialLocation}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    ShellRoute(
      builder: (context, state, child) => MobileFrame(child: child),
      routes: _userRoutes,
    ),
    ..._webRoutes,
  ],
);
