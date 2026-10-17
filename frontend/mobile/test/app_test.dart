import 'package:defiwawa/app/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  testWidgets('app boots to the map route', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: DefiWawaApp()));
    expect(find.text('DefiWawa'), findsOneWidget);
  });
}
