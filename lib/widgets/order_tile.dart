import 'package:flutter/material.dart';

import '../logic/grid_layout.dart';
import '../models/kitchen_order.dart';

/// One order's tile on the kitchen grid. A [StatefulWidget] (rather than the
/// stateless version this used to be) purely so overdue tiles can pulse on
/// their own smooth 60fps ticker — the screen above only rebuilds this
/// widget once a second (`KitchenDisplayScreen`'s `_ticker`), which isn't
/// fine-grained enough for a flash effect on its own.
class OrderTile extends StatefulWidget {
  const OrderTile({super.key, required this.order, required this.now});

  final KitchenOrder order;
  final DateTime now;

  @override
  State<OrderTile> createState() => _OrderTileState();
}

class _OrderTileState extends State<OrderTile> with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final longWait = isLongWait(widget.order.readySince, widget.now);
    if (!longWait) return _buildTile(context, 0);
    return AnimatedBuilder(
      animation: _flash,
      builder: (context, _) => _buildTile(context, _flash.value),
    );
  }

  Widget _buildTile(BuildContext context, double t) {
    final order = widget.order;
    final longWait = isLongWait(order.readySince, widget.now);
    final error = Theme.of(context).colorScheme.error;
    const base = Color(0xFF1E1E1E);

    return Container(
      decoration: BoxDecoration(
        color: longWait ? Color.lerp(base, error, t * 0.35) : base,
        borderRadius: BorderRadius.circular(16),
        border: longWait ? Border.all(color: error, width: 5 + t * 7) : null,
        boxShadow: longWait
            ? [
                BoxShadow(
                  color: error.withValues(alpha: 0.25 + t * 0.5),
                  blurRadius: 16 + t * 32,
                  spreadRadius: t * 6,
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final shortestSide =
              constraints.biggest.shortestSide.clamp(80.0, 2000.0);
          // Order number is the one thing a customer needs to spot from
          // across the room, so it gets the lion's share of the tile.
          final numberFontSize = (shortestSide * 0.44).clamp(32.0, 220.0);
          final itemFontSize = (shortestSide * 0.08).clamp(12.0, 40.0);

          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '#${order.orderNumber}',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: numberFontSize,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  shadows: longWait
                      ? [
                          Shadow(
                            color: error.withValues(alpha: 0.6 + t * 0.4),
                            blurRadius: 20 + t * 24,
                          ),
                        ]
                      : null,
                ),
              ),
              if (longWait) ...[
                SizedBox(height: itemFontSize * 0.35),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: itemFontSize * 0.7,
                    vertical: itemFontSize * 0.25,
                  ),
                  decoration: BoxDecoration(
                    color: error.withValues(alpha: 0.35 + t * 0.4),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '⚠️',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: itemFontSize * 1.1,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              SizedBox(height: itemFontSize * 0.5),
              ...order.items.map(
                (item) => Padding(
                  padding: EdgeInsets.symmetric(vertical: itemFontSize * 0.1),
                  child: Text(
                    '${item.name} × ${item.quantity}',
                    style: TextStyle(color: Colors.white, fontSize: itemFontSize),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
