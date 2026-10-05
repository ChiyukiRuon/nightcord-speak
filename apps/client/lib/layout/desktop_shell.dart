import 'package:flutter/material.dart';

class DesktopShell extends StatelessWidget {
  const DesktopShell({
    required this.navigation,
    required this.content,
    required this.navigationWidth,
    this.footer,
    this.banner,
    super.key,
  });
  final Widget navigation;
  final Widget content;
  final Widget? footer;
  final Widget? banner;
  final double navigationWidth;
  @override
  Widget build(BuildContext context) => Scaffold(
    bottomNavigationBar: footer,
    body: SafeArea(
      child: Column(
        children: [
          ?banner,
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: navigationWidth, child: navigation),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
