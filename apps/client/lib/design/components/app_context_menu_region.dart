import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';

import '../../core/platform/services.dart';

/// Identifies hits that have an application secondary-click action.
class AppContextMenuRegion extends StatefulWidget {
  const AppContextMenuRegion({
    required this.child,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final bool enabled;

  @override
  State<AppContextMenuRegion> createState() => _AppContextMenuRegionState();
}

class _AppContextMenuRegionState extends State<AppContextMenuRegion> {
  @override
  void initState() {
    super.initState();
    registerApplicationContextMenuRegion(this, _contains);
  }

  bool _contains(double x, double y) {
    if (!mounted || !widget.enabled) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final point = Offset(x, y);
    if (!(box.localToGlobal(Offset.zero) & box.size).contains(point)) {
      return false;
    }
    // Bounds alone would intercept clicks through a modal or a clipped row.
    final result = HitTestResult();
    GestureBinding.instance.hitTestInView(
      result,
      point,
      View.of(context).viewId,
    );
    return result.path.any((entry) => identical(entry.target, box));
  }

  @override
  void dispose() {
    unregisterApplicationContextMenuRegion(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(child: widget.child);
}
