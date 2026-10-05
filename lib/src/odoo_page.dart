/// A page of records plus the total count — for infinite scroll / paging.
class OdooPage<T> {
  final List<T> records;
  final int total;
  final int offset;
  final int limit;

  const OdooPage({
    required this.records,
    required this.total,
    required this.offset,
    required this.limit,
  });

  bool get hasMore => offset + records.length < total;
  int get nextOffset => offset + records.length;
}
