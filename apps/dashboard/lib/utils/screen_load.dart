/// Avoid blanking the UI when reloading a screen that already has data.
void beginScreenLoad({
  required bool hasData,
  required void Function({required bool loading, required bool refreshing, Object? error}) apply,
}) {
  apply(loading: !hasData, refreshing: hasData, error: null);
}
