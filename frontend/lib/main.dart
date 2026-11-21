import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'theme.dart';

void main() => runApp(const BelegGuardApp());

class BelegGuardApp extends StatelessWidget {
  const BelegGuardApp({super.key});

  @override
  Widget build(BuildContext context) =>
      MaterialApp(title: 'BelegGuard', debugShowCheckedModeBanner: false, theme: buildTheme(), home: const HomePage());
}
