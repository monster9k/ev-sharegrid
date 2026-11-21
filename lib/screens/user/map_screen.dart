import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/api.dart';
import '../../theme.dart';
import '../../widgets/api_content.dart';
import '../../widgets/common.dart';
import '../../widgets/glass.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, this.client});

  final ApiClient? client;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _centerLat = 16.06;
  static const _centerLng = 108.22;
  static const _radiusKm = 25.0;

  ApiClient get _api => widget.client ?? apiClient;
  late var _catalog = _api.getStations();
  Future<List<Map<String, dynamic>>>? _nearby;
  bool _activeOnly = false;
  String _query = '';

  void _setNearby(bool enabled) {
    setState(() {
      _nearby = enabled
          ? _api.getStations(
              lat: _centerLat,
              lng: _centerLng,
              radiusKm: _radiusKm,
            )
          : null;
    });
  }

  bool _located(Map<String, dynamic> station) {
    final lat = station['lat'];
    final lng = station['lng'];
    return lat is num && lng is num && lat.abs() <= 90 && lng.abs() <= 180;
  }

  bool _matches(Map<String, dynamic> station) =>
      _located(station) &&
      (_nearby == null || station['distance_km'] is num) &&
      (!_activeOnly || station['status'] == 'ACTIVE') &&
      '${station['name']} ${station['address']}'.toLowerCase().contains(_query);

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _catalog,
    builder: (context, catalog) {
      final total = catalog.data;
      return UserScaffold(
        tab: UserTab.map,
        showSimulationTag: false,
        children: [
          MobileHeader(
            title: 'Bản đồ trạm sạc',
            onBack: () => context.go('/home'),
          ),
          if (total != null)
            MutedText(
              '${total.where((station) => station['status'] == 'ACTIVE').length}/${total.length} trạm đang hoạt động',
            ),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Tìm trạm theo tên hoặc địa chỉ',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
          ),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Đang hoạt động'),
                selected: _activeOnly,
                onSelected: (value) => setState(() => _activeOnly = value),
              ),
              FilterChip(
                label: const Text('Trong 25 km từ trung tâm Đà Nẵng'),
                selected: _nearby != null,
                onSelected: _setNearby,
              ),
            ],
          ),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _nearby ?? _catalog,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) {
                return ApiErrorCard(
                  error: snapshot.error!,
                  onRetry: _nearby != null
                      ? () => _setNearby(true)
                      : () => setState(() => _catalog = _api.getStations()),
                );
              }
              final stations = (snapshot.data ?? const [])
                  .where(_matches)
                  .toList();
              if (stations.isEmpty) {
                return const AppCard(
                  child: MutedText('Không tìm thấy trạm có tọa độ phù hợp.'),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StationPlot(stations: stations),
                  const Gap(8),
                  MutedText(
                    '${stations.length} trạm có tọa độ · chạm vào điểm hoặc tên để xem trạm',
                    size: 12,
                  ),
                  for (final station in stations)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const IconBox(AppIcons.station, size: 36),
                      title: BoldText(
                        station['name']?.toString() ?? 'Trạm sạc',
                      ),
                      subtitle: MutedText(
                        station['address']?.toString() ?? '—',
                      ),
                      trailing: station['status'] == 'ACTIVE'
                          ? Pill.success('Hoạt động')
                          : const Pill('Chưa mở'),
                      onTap: () =>
                          context.go('/station/${station['station_id']}'),
                    ),
                ],
              );
            },
          ),
        ],
      );
    },
  );
}

class _StationPlot extends StatelessWidget {
  const _StationPlot({required this.stations});
  final List<Map<String, dynamic>> stations;

  @override
  Widget build(BuildContext context) {
    final coordinates = [
      for (final station in stations)
        (
          station,
          (station['lat'] as num).toDouble(),
          (station['lng'] as num).toDouble(),
        ),
    ];
    final lats = coordinates.map((station) => station.$2);
    final lngs = coordinates.map((station) => station.$3);
    final south = lats.reduce(math.min);
    final north = lats.reduce(math.max);
    final west = lngs.reduce(math.min);
    final east = lngs.reduce(math.max);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 220,
        child: ColoredBox(
          color: AppColors.sky200,
          child: LayoutBuilder(
            builder: (context, box) => Stack(
              children: [
                const Positioned(
                  top: 9,
                  left: 10,
                  child: MutedText(
                    'Sơ đồ vị trí trạm',
                    size: 12,
                    color: AppColors.skyInk,
                  ),
                ),
                for (final (station, lat, lng) in coordinates)
                  Positioned(
                    left:
                        8 +
                        (east == west ? .5 : (lng - west) / (east - west)) *
                            (box.maxWidth - 40),
                    top:
                        30 +
                        (north == south
                                ? .5
                                : (north - lat) / (north - south)) *
                            (box.maxHeight - 60),
                    child: Tooltip(
                      message: station['name']?.toString() ?? 'Trạm sạc',
                      child: InkWell(
                        onTap: () =>
                            context.go('/station/${station['station_id']}'),
                        customBorder: const CircleBorder(),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.location_on,
                            size: 18,
                            color: station['status'] == 'ACTIVE'
                                ? AppColors.skyInk
                                : AppColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
