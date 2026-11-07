import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

// Widgets from a different part of the app (a shop). The trip screen never
// uses them, but the naive app registers everything in one global catalog,
// so their schemas ride along in the system prompt of every trip request.
// This is the "Every widget, every request" problem from Fix 2.

Widget _unused(String name) => Card(
  child: Padding(
    padding: const EdgeInsets.all(16),
    child: Text('$name (shop widget)'),
  ),
);

CatalogItem _shopItem(String name, String description, JsonMap props) =>
    CatalogItem(
      name: name,
      dataSchema: S.object(
        description: description,
        properties: {
          for (final e in props.entries)
            e.key: S.string(description: e.value as String),
        },
      ),
      widgetBuilder: (ctx) => _unused(name),
    );

final List<CatalogItem> shopItems = [
  _shopItem(
    'ProductGrid',
    'A two-column grid of products from the shop catalogue, each with an '
        'image, a name, a price, a rating and an add-to-cart button. Use it '
        'when the user is browsing a category or searching for products.',
    {
      'category': 'The product category being browsed, such as "Shoes".',
      'query': 'The search query the user typed, if any.',
      'sortOrder': 'How products are sorted: popularity, price or rating.',
    },
  ),
  _shopItem(
    'ProductDetail',
    'A full-screen product page with an image gallery, the description, '
        'available sizes and colours, delivery estimates, stock levels and '
        'a large add-to-cart button. Use it when the user opens one product.',
    {
      'productId': 'The unique identifier of the product to show.',
      'selectedSize': 'The size the user has picked, if any.',
      'selectedColour': 'The colour the user has picked, if any.',
    },
  ),
  _shopItem(
    'CartSummary',
    'A summary of everything in the shopping cart, with line items, '
        'quantities, discounts, delivery fees, taxes and the grand total, '
        'plus a button to continue to checkout.',
    {
      'cartId': 'The identifier of the cart.',
      'promoCode': 'A promotional code applied to the cart, if any.',
    },
  ),
  _shopItem(
    'CheckoutForm',
    'A multi-step checkout form that collects the delivery address, the '
        'delivery method, the payment method and a final confirmation. Use '
        'it only when the user has decided to buy what is in the cart.',
    {
      'step': 'The current step: address, delivery, payment or confirm.',
      'savedAddressId': 'A saved address to pre-fill, if any.',
    },
  ),
  _shopItem(
    'OrderTracker',
    'A timeline that tracks an order from confirmation through packing, '
        'dispatch and delivery, with the courier name, the tracking number '
        'and the estimated delivery date.',
    {
      'orderId': 'The identifier of the order to track.',
      'courier': 'The name of the courier delivering the order.',
    },
  ),
  _shopItem(
    'ReviewList',
    'A list of customer reviews for a product, with star ratings, review '
        'text, photos uploaded by customers, helpfulness votes and filters '
        'for rating and verified purchases.',
    {
      'productId': 'The product whose reviews are shown.',
      'minimumRating': 'Only show reviews with at least this many stars.',
    },
  ),
  _shopItem(
    'LoyaltyCard',
    'A card showing the customer loyalty programme: current points, tier, '
        'progress to the next tier, and rewards available to redeem.',
    {'memberId': 'The loyalty programme member identifier.'},
  ),
];
