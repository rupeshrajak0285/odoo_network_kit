/// Tiny helper to build Odoo domains readably.
///
/// ```dart
/// final d = OdooDomain()
///   .where('state', '=', 'sale')
///   .where('amount_total', '>', 100)
///   .build();
/// ```
class OdooDomain {
  final List<dynamic> _items = [];

  OdooDomain where(String field, String operator, Object? value) {
    _items.add([field, operator, value]);
    return this;
  }

  OdooDomain or() {
    _items.add('|');
    return this;
  }

  OdooDomain and() {
    _items.add('&');
    return this;
  }

  OdooDomain not() {
    _items.add('!');
    return this;
  }

  List<dynamic> build() => List.unmodifiable(_items);
}
