enum ProductEventDecision { rejected }

ProductEventDecision admitProductEvent({
  required String name,
  Map<String, Object?> properties = const <String, Object?>{},
}) {
  if (name.isEmpty || properties.isEmpty) {
    return ProductEventDecision.rejected;
  }
  return ProductEventDecision.rejected;
}
