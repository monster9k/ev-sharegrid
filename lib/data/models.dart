/// Model dữ liệu dùng cho giao diện. Tên trường bám theo 19 bảng trong CLAUDE.md
/// nhưng rút gọn cho phần hiển thị (chưa nối backend).
library;

enum PortStatus { active, maintenance, offline }

enum Availability { free, busy, full }

enum TariffBand { offPeak, normal, peak }

enum NotifKind {
  scheduleChanged,
  maintenance,
  scheduled,
  shortfall,
  sessionDone,
}

class VehicleModel {
  const VehicleModel({
    required this.brand,
    required this.name,
    required this.type,
    required this.connector,
    required this.batteryKwh,
    required this.maxKw,
    this.sourceRef = 'vinfastauto.com',
  });

  final String brand;
  final String name;
  final String type; // CAR | MOTORBIKE
  final String connector; // CCS2 | Type2 | CHAdeMO | AC_HOME
  final double batteryKwh;
  final double maxKw;
  final String sourceRef;
}

class Vehicle {
  const Vehicle({
    required this.nickname,
    required this.plate,
    required this.model,
    required this.defaultSoc,
    this.isDefault = false,
  });

  final String nickname;
  final String plate;
  final VehicleModel model;
  final int defaultSoc;
  final bool isDefault;
}

class Port {
  const Port({
    required this.code,
    required this.connector,
    required this.control,
    required this.minKw,
    required this.maxKw,
    this.status = PortStatus.active,
    this.statusNote,
    this.inUse = false,
    this.futureBookings = 0,
  });

  final String code;
  final String connector;
  final String control; // CONTINUOUS | ON_OFF_SWITCH
  final double minKw;
  final double maxKw;
  final PortStatus status;
  final String? statusNote;
  final bool inUse;
  final int futureBookings;
}

class Station {
  const Station({
    required this.id,
    required this.name,
    required this.address,
    required this.cluster,
    required this.hours,
    required this.capKw,
    required this.feeVnd,
    required this.rating,
    required this.reviews,
    required this.distanceKm,
    required this.ports,
    required this.mapX,
    required this.mapY,
    required this.pinLabel,
    this.pinNote,
    this.availability = Availability.free,
    this.is24h = false,
    this.kind = 'Trạm chia sẻ',
    this.vehicles = 'Ô tô',
  });

  final int id;
  final String name;
  final String address;
  final String cluster;
  final String hours;
  final double capKw;
  final int feeVnd;
  final double rating;
  final int reviews;
  final double distanceKm;
  final List<Port> ports;

  /// Toạ độ tương đối trên bản đồ vẽ tay (0..1).
  final double mapX;
  final double mapY;
  final String pinLabel;
  final String? pinNote;
  final Availability availability;
  final bool is24h;
  final String kind;
  final String vehicles;

  double get nominalKw => ports.fold(0, (s, p) => s + p.maxKw);
}

class TariffWindow {
  const TariffWindow(this.start, this.end, this.band, this.price);

  /// Giờ trong ngày, ví dụ 9.5 = 09:30.
  final double start;
  final double end;
  final TariffBand band;
  final int price;
}

class ScheduleSlot {
  const ScheduleSlot(this.start, this.kw);

  /// Giờ bắt đầu slot 15 phút, ví dụ 8.25 = 08:15.
  final double start;
  final double kw;
}

class NotificationItem {
  const NotificationItem({
    required this.kind,
    required this.title,
    required this.body,
    required this.time,
    this.unread = false,
    this.action,
  });

  final NotifKind kind;
  final String title;
  final String body;
  final String time;
  final bool unread;
  final String? action;
}

class BookingItem {
  const BookingItem({
    required this.day,
    required this.month,
    required this.title,
    required this.subtitle,
    required this.status,
    this.warn = false,
  });

  final String day;
  final String month;
  final String title;
  final String subtitle;
  final String status;
  final bool warn;
}

class GanttBlock {
  const GanttBlock(
    this.row,
    this.start,
    this.end,
    this.label, {
    this.locked = false,
    this.shortfall = false,
    this.maintenance = false,
    this.lockedUntil,
  });

  final int row;
  final double start;
  final double end;
  final String label;
  final bool locked;
  final bool shortfall;
  final bool maintenance;
  final double? lockedUntil;
}
