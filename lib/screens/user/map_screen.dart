import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/mock_data.dart';
import '../../data/models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/danang_map.dart';
import '../../widgets/glass.dart';

/// U3 – Bản đồ & tìm trạm: lọc theo trạng thái, đầu nối, giờ mở; thẻ trạm
/// dạng bottom sheet kính.
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  Station? _selected = Mock.nguyenVanLinh;
  final _filters = <String>{'Còn trống'};

  static const _chips = [
    ('Còn trống', Icons.check_circle_outline_rounded),
    ('CCS2', AppIcons.plug),
    ('AC_HOME', AppIcons.moto),
    ('Type2', null),
    ('Đang mở', AppIcons.clock),
  ];

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F1EC),
      body: Stack(
        children: [
          Positioned.fill(
            child: DanangMap(
              stations: Mock.stations,
              selectedId: _selected?.id,
              userDot: const Offset(179, 213),
              onPinTap: (s) => setState(() => _selected = s),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 18 + top,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Glass(
                  radius: 28,
                  opacity: .66,
                  padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                  child: Row(
                    children: [
                      const IconBox(
                        AppIcons.station,
                        size: 34,
                        iconSize: 18,
                        radius: 10,
                        bg: AppColors.navy,
                        fg: Colors.white,
                      ),
                      const Gap(10),
                      Expanded(
                        child: TextField(
                          style: AppFonts.body(size: 15),
                          decoration: InputDecoration(
                            hintText: 'Tìm trạm sạc ở Đà Nẵng',
                            hintStyle: AppFonts.body(
                              size: 15,
                              color: AppColors.muted,
                            ),
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Tìm bằng giọng nói',
                        onPressed: () {},
                        icon: const Icon(
                          Icons.mic_none_rounded,
                          color: AppColors.muted,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => context.go('/profile'),
                        child: CircleAvatar(
                          radius: 17,
                          backgroundColor: AppColors.blue,
                          child: Text(
                            'NA',
                            style: AppFonts.body(
                              size: 12,
                              weight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (label, icon) in _chips) ...[
                        FilterChipX(
                          label,
                          icon: icon,
                          selected: _filters.contains(label),
                          onTap: () => setState(
                            () => _filters.contains(label)
                                ? _filters.remove(label)
                                : _filters.add(label),
                          ),
                        ),
                        const Gap(8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 12,
            top: 200 + top,
            child: Column(
              children: [
                _Fab(Icons.layers_outlined, 'Lớp bản đồ'),
                const Gap(10),
                _Fab(Icons.my_location_rounded, 'Vị trí của tôi', blue: true),
              ],
            ),
          ),
          if (_selected != null)
            DraggableScrollableSheet(
              initialChildSize: .5,
              minChildSize: .2,
              maxChildSize: .86,
              builder: (context, controller) => Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 86),
                child: Glass(
                  radius: 30,
                  opacity: .8,
                  child: _StationSheet(
                    station: _selected!,
                    controller: controller,
                    onClose: () => setState(() => _selected = null),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 14 + MediaQuery.paddingOf(context).bottom,
            child: const GlassNavBar(current: UserTab.map),
          ),
        ],
      ),
    );
  }
}

class _Fab extends StatelessWidget {
  const _Fab(this.icon, this.label, {this.blue = false});
  final IconData icon;
  final String label;
  final bool blue;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: const CircleBorder(),
    elevation: 3,
    shadowColor: const Color(0x550B1B3F),
    child: IconButton(
      tooltip: label,
      onPressed: () {},
      icon: Icon(icon, color: blue ? AppColors.blue : AppColors.ink),
    ),
  );
}

class _StationSheet extends StatelessWidget {
  const _StationSheet({
    required this.station,
    required this.controller,
    required this.onClose,
  });
  final Station station;
  final ScrollController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final s = station;
    final groups = <String, List<Port>>{};
    for (final p in s.ports) {
      groups.putIfAbsent(p.connector, () => []).add(p);
    }
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.axis,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const Gap(9),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: () => context.go('/station'),
                    child: Text(
                      s.name,
                      style: AppFonts.display(size: 21, height: 1.22),
                    ),
                  ),
                  const Gap(3),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      BoldText(vnDec(s.rating), size: 13),
                      const Gap(4),
                      for (var i = 0; i < 5; i++)
                        const Icon(
                          AppIcons.star,
                          size: 14,
                          color: AppColors.chart2,
                        ),
                      const Gap(4),
                      MutedText('(${s.reviews}) · ${s.kind}'),
                    ],
                  ),
                  MutedText(
                    '${s.address.split(',').first}, ${s.cluster.split(' ').take(2).join(' ')} · ${vnDec(s.distanceKm)} km · 5 phút',
                  ),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: s.hours,
                          style: AppFonts.body(
                            size: 13,
                            weight: FontWeight.w700,
                            color: AppColors.success,
                          ),
                        ),
                        TextSpan(
                          text: ' · trần trạm ${vnDec(s.capKw, 0)} kW',
                          style: AppFonts.body(
                            size: 13,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Đóng',
              onPressed: onClose,
              style: IconButton.styleFrom(backgroundColor: AppColors.bg),
              icon: const Icon(Icons.close_rounded, color: AppColors.muted),
            ),
          ],
        ),
        const Gap(10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _Act(
                AppIcons.route,
                'Chỉ đường',
                bg: AppColors.blue,
                fg: Colors.white,
              ),
              _Act(
                AppIcons.calendar,
                'Đặt lịch',
                bg: AppColors.sky100,
                onTap: () => context.go('/booking'),
              ),
              _Act(Icons.bookmark_border_rounded, 'Lưu', outlined: true),
              _Act(Icons.share_outlined, 'Chia sẻ', outlined: true),
            ],
          ),
        ),
        const Gap(10),
        if (groups.isNotEmpty)
          Row(
            children: [
              for (final e in groups.entries) ...[
                if (e.key != groups.keys.first) const Gap(8),
                Expanded(
                  child: _ConnectorTile(connector: e.key, ports: e.value),
                ),
              ],
            ],
          )
        else
          MutedText('Chi tiết cổng của trạm này đang được cập nhật.'),
        const Gap(10),
        Row(
          children: [
            MutedText('Giá'),
            const Gap(12),
            Expanded(
              child: Text(
                '2.400 đ/kWh (bình thường) · phí DV ${vnInt(s.feeVnd)} đ',
                textAlign: TextAlign.right,
                style: AppFonts.body(size: 13, weight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const Gap(10),
        SizedBox(
          height: 84,
          child: Row(
            children: [
              Expanded(
                flex: 14,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  alignment: Alignment.bottomLeft,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCE3EF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: MutedText('Ảnh trạm', size: 11),
                ),
              ),
              const Gap(8),
              for (var i = 0; i < 2; i++) ...[
                Expanded(
                  flex: 10,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6EAF2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                if (i == 0) const Gap(8),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Act extends StatelessWidget {
  const _Act(
    this.icon,
    this.label, {
    this.bg = Colors.transparent,
    this.fg = AppColors.blue,
    this.outlined = false,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;
  final bool outlined;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Material(
      color: bg,
      shape: StadiumBorder(
        side: outlined
            ? const BorderSide(color: AppColors.border)
            : BorderSide.none,
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap ?? () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              Icon(icon, size: 17, color: fg),
              const Gap(6),
              Text(
                label,
                style: AppFonts.body(
                  size: 13,
                  weight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ConnectorTile extends StatelessWidget {
  const _ConnectorTile({required this.connector, required this.ports});
  final String connector;
  final List<Port> ports;

  @override
  Widget build(BuildContext context) {
    final free = ports
        .where((p) => p.status == PortStatus.active && !p.inUse)
        .length;
    final codes = ports.length == 1
        ? ports.first.code
        : '${ports.first.code}–${ports.last.code}';
    final maxKw = ports.map((p) => p.maxKw).reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MutedText('$connector · $codes', size: 11, maxLines: 1),
          Text(
            '${vnDec(maxKw, maxKw % 1 == 0 ? 0 : 1)} kW',
            style: AppFonts.numbers(size: 18),
          ),
          Text(
            '$free/${ports.length} trống',
            style: AppFonts.body(
              size: 11,
              weight: FontWeight.w700,
              color: free < ports.length
                  ? AppColors.warning
                  : AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}
