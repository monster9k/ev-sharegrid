import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

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
  static const _centerLat = 16.0544;
  static const _centerLng = 108.2022;
  static const _radiusKm = 25.0;

  ApiClient get _api => widget.client ?? apiClient;
  late var _catalog = _api.getStations();
  Future<List<Map<String, dynamic>>>? _nearby;
  bool _activeOnly = false;
  String _query = '';
  Map<String, dynamic>? _selectedStation;

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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OsmStationMap(
                    stations: stations,
                    selectedStation: _selectedStation,
                    onSelectStation: (station) {
                      setState(() => _selectedStation = station);
                    },
                  ),
                  if (_selectedStation != null) ...[
                    const Gap(8),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: BoldText(
                                  _selectedStation!['name']?.toString() ??
                                      'Trạm sạc',
                                  size: 15,
                                  maxLines: 1,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () =>
                                    setState(() => _selectedStation = null),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                          const Gap(4),
                          MutedText(
                            _selectedStation!['address']?.toString() ?? '—',
                            size: 12,
                          ),
                          const Gap(8),
                          Row(
                            children: [
                              _selectedStation!['status'] == 'ACTIVE'
                                  ? Pill.success('Đang hoạt động')
                                  : const Pill('Chưa mở'),
                              if (_selectedStation!['distance_km'] is num) ...[
                                const Gap(8),
                                MutedText(
                                  'Cách ${(_selectedStation!['distance_km'] as num).toStringAsFixed(1)} km',
                                  size: 12,
                                ),
                              ],
                              const Spacer(),
                              AppButton(
                                label: 'Xem chi tiết',
                                radius: 999,
                                fontSize: 12,
                                onPressed: () => context.go(
                                  '/station/${_selectedStation!['station_id']}',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Gap(8),
                  MutedText(
                    '${stations.length} trạm trên bản đồ · bấm vào điểm để xem nhanh',
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
                      onTap: () {
                        setState(() => _selectedStation = station);
                        context.go('/station/${station['station_id']}');
                      },
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

class OsmStationMap extends StatelessWidget {
  const OsmStationMap({
    super.key,
    required this.stations,
    required this.selectedStation,
    required this.onSelectStation,
  });

  final List<Map<String, dynamic>> stations;
  final Map<String, dynamic>? selectedStation;
  final ValueChanged<Map<String, dynamic>> onSelectStation;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 280,
        decoration: BoxDecoration(
          color: AppColors.sky200,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Stack(
          children: [
            FlutterMap(
              options: const MapOptions(
                initialCenter: LatLng(16.0544, 108.2022),
                initialZoom: 12.5,
                minZoom: 9.0,
                maxZoom: 18.0,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'vn.sharegrid.ev_sharegrid',
                ),
                MarkerLayer(
                  markers: [
                    for (final station in stations)
                      Marker(
                        point: LatLng(
                          (station['lat'] as num).toDouble(),
                          (station['lng'] as num).toDouble(),
                        ),
                        width: 36,
                        height: 36,
                        child: GestureDetector(
                          onTap: () => onSelectStation(station),
                          child: _MapPin(
                            active: station['status'] == 'ACTIVE',
                            selected:
                                selectedStation?['station_id'] ==
                                station['station_id'],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 8,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const Gap(4),
                    Text(
                      'Bản đồ OpenStreetMap',
                      style: AppFonts.body(size: 11, weight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.active, required this.selected});

  final bool active;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final bgColor = active ? AppColors.blue : const Color(0xFF8E99A8);
    final size = selected ? 36.0 : 28.0;

    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.navy : Colors.white,
            width: selected ? 3.0 : 2.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          Icons.ev_station_rounded,
          color: Colors.white,
          size: selected ? 20.0 : 15.0,
        ),
      ),
    );
  }
}
