import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import '../metrics.dart';
import 'shop_catalog.dart';
import 'trip_widgets.dart';

// The trip planner's catalog, in two versions.
//
// NAIVE (what most first versions look like)
//   - every basic widget plus an unrelated shop catalog → big prompt  (Fix 2)
//   - long, chatty descriptions                                       (Fix 2)
//   - UniqueKey around every component → remounted on every update    (Fix 3)
//   - eager Row of every place, full-size image decode                (Fix 4)
//
// OPTIMISED
//   - only the widgets this screen needs, terse descriptions         (Fix 2)
//   - ValueKey(component id) + rebuild only when the data changes     (Fix 3)
//   - capped, lazy, height-bounded list, images decoded at display size (Fix 4)

// ---------------------------------------------------------------------------
// Schemas
// ---------------------------------------------------------------------------

Schema _tripHeaderSchema({required bool verbose}) => S.object(
  description: verbose
      ? 'A large, prominent header card that introduces the whole trip plan '
            'to the user. It should always be the very first thing the user '
            'sees in a trip plan, because it sets the context for everything '
            'that follows. It shows the name of the trip, a short friendly '
            'subtitle that summarises the plan, and the overall budget so the '
            'user immediately understands the scope of what is being proposed.'
      : 'Trip title card. Always first.',
  properties: {
    'title': S.string(
      description: verbose
          ? 'The title of the trip, for example "A weekend in Kampala". '
                'Keep it short, friendly and descriptive.'
          : 'Trip name.',
    ),
    'subtitle': S.string(
      description: verbose
          ? 'A one-sentence summary of the plan that tells the user what kind '
                'of weekend to expect, mentioning the mood or the highlights.'
          : 'One-line summary.',
    ),
    'budget': S.string(
      description: verbose
          ? 'The total budget for the trip, formatted for display with the '
                'currency, for example "UGX 600,000".'
          : 'Total budget with currency.',
    ),
  },
  required: ['title'],
);

Schema _dayPlanSchema({required bool verbose}) => S.object(
  description: verbose
      ? 'A card that shows the full schedule for a single day of the trip. '
            'Use one DayPlan component for each day of the trip, in order. '
            'Each day contains a list of stops with a time, a title and an '
            'optional note giving extra helpful detail about the stop, such as '
            'what to order, how to get there or what to bring along.'
      : 'One day of the trip. One per day, in order.',
  properties: {
    'day': S.string(
      description: verbose
          ? 'The label for the day, such as "Saturday" or "Day 1".'
          : 'Day label.',
    ),
    'stops': S.list(
      description: verbose
          ? 'The ordered list of stops for this day, from morning to night.'
          : 'Stops, in order.',
      items: S.object(
        properties: {
          'time': S.string(description: 'Time, e.g. "09:00".'),
          'title': S.string(description: 'What happens.'),
          'note': S.string(description: 'Optional short tip.'),
        },
        required: ['title'],
      ),
    ),
  },
  required: ['day', 'stops'],
);

Schema _placeCarouselSchema({required bool verbose}) => S.object(
  description: verbose
      ? 'A horizontally scrolling carousel of recommended places, each shown '
            'as a card with a photo, the name of the place, the area of the '
            'city it is in and a rough price level. Use it to recommend places '
            'to eat, drink, visit or stay. Include as many good places as you '
            'can think of so the user has plenty of choice.'
      : 'Recommended places with photos. 6–10 places.',
  properties: {
    'title': S.string(description: 'Carousel heading.'),
    'places': S.list(
      description: verbose
          ? 'All of the places to show in the carousel.'
          : 'Places, best first.',
      items: S.object(
        properties: {
          'name': S.string(description: 'Place name.'),
          'area': S.string(description: 'Neighbourhood.'),
          'price': S.string(description: r'Price level, e.g. "$$".'),
          'photoSeed': S.string(
            description: 'One lowercase word describing the place, '
                'e.g. "market". Used to pick a photo. Never a URL.',
          ),
        },
        required: ['name', 'photoSeed'],
      ),
    ),
  },
  required: ['places'],
);

Schema _budgetSchema({required bool verbose}) => S.object(
  description: verbose
      ? 'A summary card that breaks the total budget of the trip down into '
            'categories such as transport, food, activities and accommodation, '
            'so that the user can clearly see where their money will go and '
            'adjust their plans if something looks too expensive.'
      : 'Budget breakdown. Always last.',
  properties: {
    'currency': S.string(description: 'Currency code, e.g. "UGX".'),
    'lines': S.list(
      items: S.object(
        properties: {
          'label': S.string(description: 'Category.'),
          'amount': S.number(description: 'Amount.'),
        },
        required: ['label', 'amount'],
      ),
    ),
  },
  required: ['lines'],
);

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

String _money(String currency, num amount) {
  final digits = amount.round().toString();
  final grouped = digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return currency.isEmpty ? grouped : '$currency $grouped';
}

Widget _budgetCard(JsonMap d, {Key? Function(int i, String label)? keyFor}) {
  final currency = str(d['currency']);
  final lines = maps(d['lines']);
  final total = lines.fold<num>(0, (sum, l) => sum + numOf(l['amount']));
  return Card(
    margin: const EdgeInsets.symmetric(vertical: 8),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          for (final (i, l) in lines.indexed)
            BudgetLine(
              key: keyFor?.call(i, str(l['label'])),
              label: str(l['label']),
              amount: _money(currency, numOf(l['amount'])),
            ),
          const Divider(),
          BudgetLine(label: 'Total', amount: _money(currency, total)),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// NAIVE builders
// ---------------------------------------------------------------------------

/// A new UniqueKey on every build tells Flutter "this is a different widget":
/// the old subtree is thrown away and rebuilt from scratch, every update.
Widget _fresh(Widget child) => KeyedSubtree(key: UniqueKey(), child: child);

final List<CatalogItem> _naiveTripItems = [
  CatalogItem(
    name: 'TripHeader',
    dataSchema: _tripHeaderSchema(verbose: true),
    widgetBuilder: (ctx) {
      Metrics.instance.markComponentBuilt();
      final d = ctx.data as JsonMap;
      return _fresh(
        TripHeaderView(
          title: str(d['title']),
          subtitle: str(d['subtitle']),
          budget: str(d['budget']),
        ),
      );
    },
  ),
  CatalogItem(
    name: 'DayPlan',
    dataSchema: _dayPlanSchema(verbose: true),
    widgetBuilder: (ctx) {
      Metrics.instance.markComponentBuilt();
      final d = ctx.data as JsonMap;
      return _fresh(
        DayCard(
          day: str(d['day']),
          children: [
            for (final s in maps(d['stops']))
              StopRow(
                time: str(s['time']),
                title: str(s['title']),
                note: str(s['note']),
              ),
          ],
        ),
      );
    },
  ),
  CatalogItem(
    name: 'PlaceCarousel',
    dataSchema: _placeCarouselSchema(verbose: true),
    widgetBuilder: (ctx) {
      Metrics.instance.markComponentBuilt();
      final d = ctx.data as JsonMap;
      // Every place, built eagerly, each decoding a 2400×1600 photo
      // into a 180×110 box.
      return _fresh(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(str(d['title']).isEmpty ? 'Places' : str(d['title'])),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final p in maps(d['places']))
                    PlaceTile(
                      name: str(p['name']),
                      area: str(p['area']),
                      price: str(p['price']),
                      imageUrl: photoUrl(
                        str(p['photoSeed']),
                        width: 2400,
                        height: 1600,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  ),
  CatalogItem(
    name: 'BudgetBreakdown',
    dataSchema: _budgetSchema(verbose: true),
    widgetBuilder: (ctx) {
      Metrics.instance.markComponentBuilt();
      return _fresh(_budgetCard(ctx.data as JsonMap));
    },
  ),
];

/// Everything the app has ever registered, sent on every request.
Catalog naiveCatalog() => BasicCatalogItems.asCatalog().copyWith(
  newItems: [..._naiveTripItems, ...shopItems],
);

// ---------------------------------------------------------------------------
// OPTIMISED builders
// ---------------------------------------------------------------------------

const int _maxPlaces = 12;

final List<CatalogItem> _optimisedTripItems = [
  CatalogItem(
    name: 'TripHeader',
    dataSchema: _tripHeaderSchema(verbose: false),
    widgetBuilder: (ctx) {
      Metrics.instance.markComponentBuilt();
      final d = ctx.data as JsonMap;
      return DataMemo(
        key: ValueKey(ctx.id),
        data: d,
        builder: () => TripHeaderView(
          title: str(d['title']),
          subtitle: str(d['subtitle']),
          budget: str(d['budget']),
        ),
      );
    },
  ),
  CatalogItem(
    name: 'DayPlan',
    dataSchema: _dayPlanSchema(verbose: false),
    widgetBuilder: (ctx) {
      Metrics.instance.markComponentBuilt();
      final d = ctx.data as JsonMap;
      return DataMemo(
        key: ValueKey(ctx.id),
        data: d,
        builder: () => DayCard(
          day: str(d['day']),
          children: [
            for (final (i, s) in maps(d['stops']).indexed)
              StopRow(
                key: ValueKey('$i:${str(s['title'])}'),
                time: str(s['time']),
                title: str(s['title']),
                note: str(s['note']),
              ),
          ],
        ),
      );
    },
  ),
  CatalogItem(
    name: 'PlaceCarousel',
    dataSchema: _placeCarouselSchema(verbose: false),
    widgetBuilder: (ctx) {
      Metrics.instance.markComponentBuilt();
      final d = ctx.data as JsonMap;
      final double dpr = MediaQuery.devicePixelRatioOf(ctx.buildContext);
      final int decodeWidth = (180 * dpr).round();
      // Cap the input: the model may ignore the "6–10" in the schema.
      final places = maps(d['places']).take(_maxPlaces).toList();
      return DataMemo(
        key: ValueKey(ctx.id),
        data: d,
        builder: () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(str(d['title']).isEmpty ? 'Places' : str(d['title'])),
            // The builder decides the height, not the model.
            SizedBox(
              height: 196,
              // Lazy: only visible tiles are built.
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: places.length,
                itemBuilder: (context, i) {
                  final p = places[i];
                  return PlaceTile(
                    key: ValueKey('$i:${str(p['name'])}'),
                    name: str(p['name']),
                    area: str(p['area']),
                    price: str(p['price']),
                    imageUrl: photoUrl(
                      str(p['photoSeed']),
                      width: math.min(720, decodeWidth * 2),
                      height: math.min(480, (decodeWidth * 4 / 3).round()),
                    ),
                    decodeWidth: decodeWidth,
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  ),
  CatalogItem(
    name: 'BudgetBreakdown',
    dataSchema: _budgetSchema(verbose: false),
    widgetBuilder: (ctx) {
      Metrics.instance.markComponentBuilt();
      final d = ctx.data as JsonMap;
      return DataMemo(
        key: ValueKey(ctx.id),
        data: d,
        builder: () =>
            _budgetCard(d, keyFor: (i, label) => ValueKey('$i:$label')),
      );
    },
  ),
];

/// Only what the trip screen needs.
Catalog optimisedCatalog() => BasicCatalogItems.asNoAssetCatalog()
    .copyWithout(
      itemsToRemove: [
        BasicCatalogItems.checkBox,
        BasicCatalogItems.choicePicker,
        BasicCatalogItems.dateTimeInput,
        BasicCatalogItems.icon,
        BasicCatalogItems.list,
        BasicCatalogItems.modal,
        BasicCatalogItems.slider,
        BasicCatalogItems.tabs,
        BasicCatalogItems.textField,
      ],
    )
    .copyWith(newItems: _optimisedTripItems);

// ---------------------------------------------------------------------------
// DataMemo: rebuild a component's subtree only when its data changes
// ---------------------------------------------------------------------------

/// Returns the SAME widget instance while [data] is unchanged. When a parent
/// rebuilds and gets back an identical widget instance, Flutter skips that
/// whole subtree. Combined with a stable key, a streamed update to one
/// component no longer rebuilds its siblings.
class DataMemo extends StatefulWidget {
  const DataMemo({super.key, required this.data, required this.builder});

  final Object? data;
  final Widget Function() builder;

  @override
  State<DataMemo> createState() => _DataMemoState();
}

class _DataMemoState extends State<DataMemo> {
  static const _equality = DeepCollectionEquality();
  Widget? _cached;
  Object? _lastData;

  @override
  Widget build(BuildContext context) {
    if (_cached == null || !_equality.equals(_lastData, widget.data)) {
      _cached = widget.builder();
      // Copy, in case the source map is updated in place later.
      _lastData = _deepCopy(widget.data);
    }
    return _cached!;
  }

  static Object? _deepCopy(Object? v) => switch (v) {
    final Map<Object?, Object?> m => {
      for (final e in m.entries) e.key: _deepCopy(e.value),
    },
    final List<Object?> l => [for (final x in l) _deepCopy(x)],
    _ => v,
  };
}
