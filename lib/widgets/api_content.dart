import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/api.dart';
import 'common.dart';

class ApiErrorCard extends StatelessWidget {
  const ApiErrorCard({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MutedText(
          error is ApiException
              ? (error as ApiException).userMessage
              : 'Không thể tải dữ liệu từ máy chủ.',
        ),
        if (error is ApiException && (error as ApiException).statusCode == 401)
          TextButton(
            onPressed: () => context.go('/login'),
            child: const Text('Đăng nhập'),
          )
        else if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Thử lại')),
      ],
    ),
  );
}

class SignInCard extends StatelessWidget {
  const SignInCard(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MutedText(message),
        TextButton(
          onPressed: () => context.go('/login'),
          child: const Text('Đăng nhập'),
        ),
      ],
    ),
  );
}
