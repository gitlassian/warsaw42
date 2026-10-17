import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'router/app_router.dart';

class DefiWawaApp extends StatelessWidget {
  const DefiWawaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'DefiWawa',
      theme: AppTheme.light,
      routerConfig: appRouter,
    );
  }
}
