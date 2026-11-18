/// Dữ liệu mẫu (nhãn Mô phỏng) cho toàn bộ giao diện. Số liệu không phải đo thật.
library;

import 'models.dart';

class Mock {
  Mock._();

  // ---------------------------------------------------------------- Xe
  static const vf3 = VehicleModel(
    brand: 'VinFast',
    name: 'VF 3',
    type: 'CAR',
    connector: 'CCS2',
    batteryKwh: 18.64,
    maxKw: 24,
    sourceRef: 'vinfastauto.com',
  );
  static const vf5 = VehicleModel(
    brand: 'VinFast',
    name: 'VF 5 Plus',
    type: 'CAR',
    connector: 'CCS2',
    batteryKwh: 37.23,
    maxKw: 50,
    sourceRef: 'vinfastauto.com',
  );
  static const vf6 = VehicleModel(
    brand: 'VinFast',
    name: 'VF 6 Eco',
    type: 'CAR',
    connector: 'CCS2',
    batteryKwh: 59.6,
    maxKw: 100,
    sourceRef: 'vinfastauto.com',
  );
  static const vf7 = VehicleModel(
    brand: 'VinFast',
    name: 'VF 7 Eco',
    type: 'CAR',
    connector: 'CCS2',
    batteryKwh: 59.6,
    maxKw: 110,
    sourceRef: 'vinfastauto.com',
  );
  static const vf8 = VehicleModel(
    brand: 'VinFast',
    name: 'VF 8 Eco',
    type: 'CAR',
    connector: 'CCS2',
    batteryKwh: 87.7,
    maxKw: 149,
    sourceRef: 'vinfastauto.com',
  );
  static const limoGreen = VehicleModel(
    brand: 'VinFast',
    name: 'Limo Green',
    type: 'CAR',
    connector: 'CCS2',
    batteryKwh: 60.13,
    maxKw: 80,
    sourceRef: 'vinfastauto.com',
  );
  static const vfe34 = VehicleModel(
    brand: 'VinFast',
    name: 'VF e34',
    type: 'CAR',
    connector: 'CCS2',
    batteryKwh: 42.0,
    maxKw: 60,
    sourceRef: 'vinfastauto.com',
  );
  static const evo200 = VehicleModel(
    brand: 'VinFast',
    name: 'Evo200',
    type: 'MOTORBIKE',
    connector: 'AC_HOME',
    batteryKwh: 3.5,
    maxKw: 1,
    sourceRef: 'vinfastauto.com',
  );
  static const evo200Lite = VehicleModel(
    brand: 'VinFast',
    name: 'Evo200 Lite',
    type: 'MOTORBIKE',
    connector: 'AC_HOME',
    batteryKwh: 3.5,
    maxKw: 1,
    sourceRef: 'vinfastauto.com',
  );
  static const feliz = VehicleModel(
    brand: 'VinFast',
    name: 'Feliz S',
    type: 'MOTORBIKE',
    connector: 'AC_HOME',
    batteryKwh: 3.5,
    maxKw: 1,
    sourceRef: 'vinfastauto.com',
  );
  static const klaraS = VehicleModel(
    brand: 'VinFast',
    name: 'Klara S 2022',
    type: 'MOTORBIKE',
    connector: 'AC_HOME',
    batteryKwh: 3.5,
    maxKw: 1,
    sourceRef: 'vinfastauto.com',
  );
  static const ventoS = VehicleModel(
    brand: 'VinFast',
    name: 'Vento S',
    type: 'MOTORBIKE',
    connector: 'AC_HOME',
    batteryKwh: 3.5,
    maxKw: 1,
    sourceRef: 'vinfastauto.com',
  );
  static const theonS = VehicleModel(
    brand: 'VinFast',
    name: 'Theon S',
    type: 'MOTORBIKE',
    connector: 'AC_HOME',
    batteryKwh: 3.5,
    maxKw: 1,
    sourceRef: 'vinfastauto.com',
  );
  static const atto3Dyn = VehicleModel(
    brand: 'BYD',
    name: 'Atto 3 Dynamic',
    type: 'CAR',
    connector: 'CCS2',
    batteryKwh: 49.92,
    maxKw: 70,
    sourceRef: 'byd.com',
  );
  static const atto3Prem = VehicleModel(
    brand: 'BYD',
    name: 'Atto 3 Premium',
    type: 'CAR',
    connector: 'CCS2',
    batteryKwh: 60.48,
    maxKw: 88,
    sourceRef: 'byd.com',
  );
  static const atto3 = atto3Prem;
  static const dolphin = VehicleModel(
    brand: 'BYD',
    name: 'Dolphin',
    type: 'CAR',
    connector: 'CCS2',
    batteryKwh: 50.25,
    maxKw: 60,
    sourceRef: 'byd.com',
  );
  static const ioniq5Excl = VehicleModel(
    brand: 'Hyundai',
    name: 'Ioniq 5 Exclusive',
    type: 'CAR',
    connector: 'CCS2',
    batteryKwh: 58.0,
    maxKw: 350,
    sourceRef: 'hyundai.thanhcong.vn',
  );
  static const ioniq5Prest = VehicleModel(
    brand: 'Hyundai',
    name: 'Ioniq 5 Prestige',
    type: 'CAR',
    connector: 'CCS2',
    batteryKwh: 72.6,
    maxKw: 350,
    sourceRef: 'hyundai.thanhcong.vn',
  );
  static const ioniq5 = ioniq5Prest;
  static const wulingMini = VehicleModel(
    brand: 'Wuling',
    name: 'HongGuang MiniEV',
    type: 'CAR',
    connector: 'AC_HOME',
    batteryKwh: 13.9,
    maxKw: 2,
    sourceRef: 'wuling-ev.vn',
  );

  static const vehicleModels = [
    vf3,
    vf5,
    vf6,
    vf7,
    vf8,
    limoGreen,
    vfe34,
    evo200,
    evo200Lite,
    feliz,
    klaraS,
    ventoS,
    theonS,
    atto3Dyn,
    atto3Prem,
    dolphin,
    ioniq5Excl,
    ioniq5Prest,
    wulingMini,
  ];

  static const vehicles = [
    Vehicle(
      nickname: 'VFe34 Gia đình',
      plate: '43A-678.90',
      model: vfe34,
      defaultSoc: 85,
      isDefault: true,
    ),
    Vehicle(
      nickname: 'Xe máy Feliz',
      plate: '43-K1 555.66',
      model: feliz,
      defaultSoc: 90,
    ),
  ];

  // ---------------------------------------------------------------- Trạm
  static const nvlPorts = [
    Port(
      code: 'P1',
      connector: 'CCS2',
      control: 'CONTINUOUS',
      minKw: 1.4,
      maxKw: 11,
      futureBookings: 4,
    ),
    Port(
      code: 'P2',
      connector: 'CCS2',
      control: 'CONTINUOUS',
      minKw: 1.4,
      maxKw: 11,
      status: PortStatus.maintenance,
      statusNote: 'Bảo trì đến 14:00',
    ),
    Port(
      code: 'P3',
      connector: 'CCS2',
      control: 'CONTINUOUS',
      minKw: 1.4,
      maxKw: 11,
      inUse: true,
      futureBookings: 6,
    ),
    Port(
      code: 'P4',
      connector: 'Type2',
      control: 'CONTINUOUS',
      minKw: 1.4,
      maxKw: 22,
      futureBookings: 3,
    ),
    Port(
      code: 'P5',
      connector: 'AC_HOME',
      control: 'ON_OFF_SWITCH',
      minKw: 2.2,
      maxKw: 2.2,
      futureBookings: 2,
    ),
  ];

  static const nguyenVanLinh = Station(
    id: 11,
    name: 'Trạm ShareGrid Nguyễn Văn Linh',
    address: '85 Nguyễn Văn Linh, phường Hải Châu, Đà Nẵng',
    cluster: 'Hải Châu – Trung tâm',
    hours: 'Mở cửa 24/7',
    capKw: 40,
    feeVnd: 10000,
    rating: 4.6,
    reviews: 212,
    distanceKm: 1.4,
    ports: nvlPorts,
    mapX: 0.282,
    mapY: 0.344,
    pinLabel: '11 kW',
    pinNote: '2,4k',
    is24h: true,
  );

  static const bachDang = Station(
    id: 10,
    name: 'Trạm ShareGrid Bạch Đằng',
    address: '120 Bạch Đằng, phường Hải Châu, Đà Nẵng',
    cluster: 'Hải Châu – Trung tâm',
    hours: '06:00 – 23:00',
    capKw: 22,
    feeVnd: 5000,
    rating: 4.4,
    reviews: 87,
    distanceKm: 2.1,
    ports: [
      Port(
        code: 'P1',
        connector: 'CCS2',
        control: 'CONTINUOUS',
        minKw: 1.4,
        maxKw: 7.4,
      ),
      Port(
        code: 'P2',
        connector: 'CCS2',
        control: 'CONTINUOUS',
        minKw: 1.4,
        maxKw: 7.4,
      ),
      Port(
        code: 'P3',
        connector: 'AC_HOME',
        control: 'ON_OFF_SWITCH',
        minKw: 2.2,
        maxKw: 2.2,
      ),
      Port(
        code: 'P4',
        connector: 'Type2',
        control: 'CONTINUOUS',
        minKw: 1.4,
        maxKw: 11,
        status: PortStatus.maintenance,
      ),
    ],
    mapX: 0.246,
    mapY: 0.242,
    pinLabel: '7,4 kW',
    pinNote: '2,4k',
    availability: Availability.busy,
    vehicles: 'Ô tô & xe máy',
  );

  static const stations = [
    nguyenVanLinh,
    bachDang,
    Station(
      id: 21,
      name: 'Trạm công cộng Điện Biên Phủ',
      address: 'Điện Biên Phủ, Thanh Khê',
      cluster: 'Hải Châu – Trung tâm',
      hours: '06:00 – 22:00',
      capKw: 44,
      feeVnd: 8000,
      rating: 4.2,
      reviews: 64,
      distanceKm: 3.2,
      ports: [],
      mapX: 0.067,
      mapY: 0.173,
      pinLabel: '22 kW',
      pinNote: '3,2k',
      kind: 'Trạm công cộng',
    ),
    Station(
      id: 31,
      name: 'Trạm Sơn Trà – Ngô Quyền',
      address: 'Ngô Quyền, Sơn Trà',
      cluster: 'Sơn Trà – Ven biển',
      hours: '05:00 – 23:00',
      capKw: 33,
      feeVnd: 8000,
      rating: 4.3,
      reviews: 41,
      distanceKm: 2.6,
      ports: [],
      mapX: 0.646,
      mapY: 0.178,
      pinLabel: '11 kW',
      pinNote: 'Đông',
      availability: Availability.busy,
    ),
    Station(
      id: 32,
      name: 'Điểm sạc xe máy An Hải',
      address: 'Phạm Văn Đồng, An Hải',
      cluster: 'Sơn Trà – Ven biển',
      hours: '06:00 – 22:00',
      capKw: 13.2,
      feeVnd: 3000,
      rating: 4.5,
      reviews: 23,
      distanceKm: 2.9,
      ports: [],
      mapX: 0.646,
      mapY: 0.31,
      pinLabel: 'Xe máy',
      pinNote: '4/6',
      vehicles: 'Xe máy',
    ),
    Station(
      id: 22,
      name: 'Trạm Thanh Khê – Hà Huy Tập',
      address: 'Hà Huy Tập, Thanh Khê',
      cluster: 'Hải Châu – Trung tâm',
      hours: '06:00 – 22:00',
      capKw: 22,
      feeVnd: 8000,
      rating: 4.0,
      reviews: 18,
      distanceKm: 3.8,
      ports: [],
      mapX: 0.051,
      mapY: 0.296,
      pinLabel: 'Hết cổng',
      availability: Availability.full,
    ),
  ];

  // ---------------------------------------------------------------- Biểu giá
  static const tariff = [
    TariffWindow(0, 4, TariffBand.offPeak, 1600),
    TariffWindow(4, 9.5, TariffBand.normal, 2400),
    TariffWindow(9.5, 11.5, TariffBand.peak, 4000),
    TariffWindow(11.5, 17, TariffBand.normal, 2400),
    TariffWindow(17, 20, TariffBand.peak, 4000),
    TariffWindow(20, 22, TariffBand.normal, 2400),
    TariffWindow(22, 24, TariffBand.offPeak, 1600),
  ];

  static TariffBand bandAt(double hour) {
    for (final w in tariff) {
      if (hour >= w.start && hour < w.end) return w.band;
    }
    return TariffBand.normal;
  }

  // ---------------------------------------------------------------- Lịch sạc
  /// Lịch request #R-5012 tại cổng P3 (v3), 08:00 → lấy xe 17:30.
  static const schedule = [
    ScheduleSlot(8.0, 11),
    ScheduleSlot(8.25, 11),
    ScheduleSlot(8.5, 7.4),
    ScheduleSlot(8.75, 7.4),
    ScheduleSlot(9.0, 11),
    ScheduleSlot(9.25, 11),
    ScheduleSlot(11.5, 11),
    ScheduleSlot(11.75, 11),
    ScheduleSlot(12.0, 10.3),
  ];

  /// Mức độ đông theo giờ 6h–22h (0..1).
  static const popularTimes = [
    0.10,
    0.22,
    0.38,
    0.46,
    0.40,
    0.34,
    0.42,
    0.36,
    0.26,
    0.38,
    0.58,
    0.82,
    0.96,
    0.88,
    0.64,
    0.40,
    0.20,
  ];

  // ---------------------------------------------------------------- Thông báo
  static const notifications = [
    NotificationItem(
      kind: NotifKind.scheduleChanged,
      title: 'Lịch sạc đã thay đổi · v2 → v3',
      body:
          'Có 2 yêu cầu mới trong cụm Hải Châu. Slot 08:30–09:00 giảm từ 11 kW còn 7,4 kW; giờ đạt 80% đổi 12:00 → 12:15. Không phát sinh điện thiếu.',
      time: '09:15',
      unread: true,
      action: 'Xem lịch mới',
    ),
    NotificationItem(
      kind: NotifKind.maintenance,
      title: 'Cổng P2 chuyển sang bảo trì',
      body:
          'Chủ trạm báo bảo trì đến 14:00. Lịch tương lai của bạn đã chuyển sang cổng P3 (cùng đầu nối CCS2), phần đã sạc giữ nguyên.',
      time: '08:40',
      unread: true,
    ),
    NotificationItem(
      kind: NotifKind.scheduled,
      title: 'Lịch đã được xếp · OPTIMAL',
      body:
          'Request #R-5012: 22,77 kWh tại cổng P3, dự kiến 80% lúc 12:00, chi phí điện 54.700 đ.',
      time: 'Hôm qua 21:04',
    ),
    NotificationItem(
      kind: NotifKind.shortfall,
      title: 'Có thể thiếu 0,6 kWh',
      body:
          'Request #R-4870 thiếu 0,6 kWh vì cụm Sơn Trà đã chạm trần 350 kW trong các slot trước giờ rời 18:00. Bạn có thể lùi giờ lấy xe để nạp đủ.',
      time: '03/12',
    ),
    NotificationItem(
      kind: NotifKind.sessionDone,
      title: 'Phiên sạc hoàn tất',
      body:
          'Đã nạp 18,4 kWh · điện 44.160 đ + phí dịch vụ 10.000 đ = 54.160 đ.',
      time: '02/12',
    ),
  ];

  static const upcoming = [
    BookingItem(
      day: '08',
      month: 'TH12',
      title: 'ShareGrid Bạch Đằng · P1',
      subtitle: 'Đỗ 13:00 – 18:00 · sạc 13:15 – 15:30',
      status: '✓ CONFIRMED',
    ),
    BookingItem(
      day: '10',
      month: 'TH12',
      title: 'Xe máy Feliz · Bạch Đằng',
      subtitle: 'Đỗ 19:00 – 06:00 sáng hôm sau',
      status: '◷ PENDING',
      warn: true,
    ),
  ];

  // ---------------------------------------------------------------- HOST
  static const hostGantt = [
    GanttBlock(0, 8, 9.25, 'R-5033', locked: true),
    GanttBlock(0, 10, 11.25, 'R-5040'),
    GanttBlock(0, 12, 13, 'R-5047'),
    GanttBlock(0, 13.25, 15, 'R-5051 −1,2', shortfall: true),
    GanttBlock(1, 6, 14, 'Bảo trì đến 14:00', maintenance: true),
    GanttBlock(2, 8, 9.5, 'R-5012', lockedUntil: 9.25),
    GanttBlock(2, 11.5, 12.25, ''),
    GanttBlock(2, 13, 14.5, 'R-5060'),
    GanttBlock(2, 20, 21.5, 'R-5072'),
    GanttBlock(3, 9, 10.5, 'R-5021', lockedUntil: 9.25),
    GanttBlock(3, 15, 17, 'R-5066'),
    GanttBlock(4, 6, 8, 'R-4990', locked: true),
    GanttBlock(4, 19, 22, 'R-5080'),
  ];

  /// Tổng công suất trạm theo giờ 6h–22h (kW), trần 40 kW.
  static const stationLoad = [
    2.2,
    9.0,
    40.0,
    33.0,
    22.0,
    24.0,
    35.0,
    40.0,
    31.0,
    22.0,
    26.0,
    12.0,
    8.0,
    13.0,
    15.0,
    13.0,
    2.2,
  ];

  // ---------------------------------------------------------------- ADMIN
  static const queueDepth = [
    3.0,
    2.0,
    4.0,
    3.0,
    7.0,
    9.0,
    4.0,
    4.0,
    3.0,
    3.0,
    4.0,
  ];

  /// Số lượt đặt mỗi giờ cụm Hải Châu: đo được 0–9h, dự báo 9–24h.
  static const arrivalsMeasured = [
    4.0,
    2.0,
    2.0,
    1.0,
    3.0,
    8.0,
    22.0,
    48.0,
    61.0,
    44.0,
  ];
  static const arrivalsForecast = [
    46.0,
    38.0,
    35.0,
    40.0,
    44.0,
    39.0,
    36.0,
    47.0,
    63.0,
    70.0,
    58.0,
    41.0,
    28.0,
    15.0,
    8.0,
    5.0,
  ];

  /// Thời gian giải (giây) theo active requests 100/500/1k/2,5k/5k/10k.
  static const solveMilp = [0.2, 0.8, 1.4, 4.1, 9.8, 23.5];
  static const solveLp = [0.05, 0.15, 0.31, 0.9, 2.1, 5.2];
  static const solveLlf = [0.01, 0.02, 0.05, 0.12, 0.26, 0.6];
  static const solveMonolithic = [0.3, 3.2, 14.0];
}
