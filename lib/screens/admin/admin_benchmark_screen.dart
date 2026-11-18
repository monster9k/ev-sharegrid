import 'package:flutter/material.dart';

import '../../widgets/web_shell.dart';
import 'admin_common.dart';

/// A5 – Chỉ công bố số benchmark sau khi có artifact đo được.
class AdminBenchmarkScreen extends StatelessWidget {
  const AdminBenchmarkScreen({super.key});

  @override
  Widget build(BuildContext context) => WebShell(
    portal: Portal.admin,
    route: '/admin/benchmark',
    eyebrow: 'Quản trị · số đo cần artifact tái lập',
    title: 'Benchmark thuật toán',
    children: const [
      WebCard(
        children: [
          InfoNote(
            'Chưa có dữ liệu benchmark thật. Các số KPI minh hoạ đã được gỡ khỏi màn này; hãy bổ sung artifact benchmark có scenario, seed và phiên bản code trước khi công bố kết quả.',
            warn: true,
          ),
        ],
      ),
    ],
  );
}
