import '../models/kitchen_order.dart';

/// Number of grid columns for a given number of main-tile orders.
/// 1 column if <=1 order, 2 columns if <=4 orders, else 3 columns.
int gridColumnsForCount(int count) {
  if (count <= 1) return 1;
  if (count <= 4) return 2;
  return 3;
}

/// Number of grid rows needed for [count] orders laid out in [columns] columns.
int gridRowsForCount(int count, int columns) {
  if (columns <= 0) return 0;
  return (count / columns).ceil();
}

/// Result of splitting the full orders list into what fits on the main grid
/// versus what overflows into the bottom bar.
class GridSplit {
  const GridSplit({required this.mainTiles, required this.overflow});

  final List<KitchenOrder> mainTiles;
  final List<KitchenOrder> overflow;
}

/// Orders are already sorted oldest-ready-first by the backend — never re-sort.
/// At most the first 6 orders go on the main grid; anything beyond that is
/// overflow.
GridSplit splitOrdersForGrid(List<KitchenOrder> orders) {
  if (orders.length <= 6) {
    return GridSplit(mainTiles: orders, overflow: const []);
  }
  return GridSplit(
    mainTiles: orders.sublist(0, 6),
    overflow: orders.sublist(6),
  );
}

const kLongWaitThreshold = Duration(minutes: 5);

/// An order counts as a long wait once it has been ready for MORE than
/// [kLongWaitThreshold] — exactly 5:00 is not yet flagged, 5:01 is.
bool isLongWait(DateTime readySince, DateTime now) {
  return now.difference(readySince) > kLongWaitThreshold;
}
