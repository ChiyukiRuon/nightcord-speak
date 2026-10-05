import 'package:flutter/material.dart';

import 'desktop_shell.dart';
import 'mobile_shell.dart';

enum LayoutClass { desktop, mobile }

/// Layout follows available width, including narrow desktop browser windows.
LayoutClass layoutClassFor(double width) => width >= 760 ? LayoutClass.desktop : LayoutClass.mobile;

class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({
    required this.navigation,
    required this.content,
    required this.mobileTitle,
    this.footer,
    this.banner,
    this.navigationWidth = 280,
    this.mobileActions,
    this.mobileNavigationBuilder,
    this.mobileDetailTitle,
    super.key,
  });
  final Widget navigation;
  final Widget content;
  final Widget? footer;
  final Widget? banner;
  final String mobileTitle;
  final double navigationWidth;
  final List<Widget>? mobileActions;

  final Widget Function(VoidCallback openDetail)? mobileNavigationBuilder;
  final String? mobileDetailTitle;
  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  bool _detail = false;
  void _open() => setState(() => _detail = true);
  void _back() => setState(() => _detail = false);
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      return layoutClassFor(constraints.maxWidth) == LayoutClass.desktop
          ? DesktopShell(
              navigation: widget.navigation,
              content: widget.content,
              footer: widget.footer,
              banner: widget.banner,
              navigationWidth: widget.navigationWidth,
            )
          : MobileShell(
              navigation: widget.mobileNavigationBuilder?.call(_open) ?? widget.navigation,
              content: widget.content,
              showingDetail: _detail,
              onBack: _back,
              footer: widget.footer,
              banner: widget.banner,
              title: _detail ? widget.mobileDetailTitle ?? widget.mobileTitle : widget.mobileTitle,
              actions: widget.mobileActions,
            );
    },
  );
}
