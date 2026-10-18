import 'package:defiwawa/app/router/route_handle.dart';
import 'package:defiwawa/features/aeds/models/aed.dart';
import 'package:defiwawa/features/aeds/providers/aeds_provider.dart';
import 'package:defiwawa/features/discovery/presentation/sheets/discovery_sheets.dart';
import 'package:defiwawa/shared/geo/geo.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _aed = Aed(
  id: '7',
  location: LngLat(21.01, 52.23),
  venueName: 'Urząd Dzielnicy',
  address: 'Rakowiecka 25/27, 02-517 Warszawa',
  entrance: 'Wejście główne, recepcja',
  indoor: true,
  floor: 0,
  publicAccess: PublicAccess.public,
  operationalStatus: OperationalStatus.unknown,
  schedule: AlwaysOpen(),
  sourceHours: '24/7',
);

class _ReadyAeds extends AedsNotifier {
  @override
  AedsState build() => AedsState(now: DateTime.now(), status: LoadStatus.ready, aeds: const [_aed], byId: {'7': _aed});
}

void main() {
  test('routes map to sheet heights, close buttons and back targets like the web handles', () {
    expect(RouteHandle.of('/').floating, true);
    expect(RouteHandle.of('/aed/7').close, RouteClose.selection);
    expect(RouteHandle.of('/aed/7').selectedId, '7');
    expect(RouteHandle.of('/aed/7/navigate').sheet, SheetSnap.compact);
    expect(RouteHandle.of('/aed/7/navigate').parent, '/aed/7');
    expect(RouteHandle.of('/report/7').sheet, SheetSnap.expanded);
    expect(RouteHandle.of('/coverage').close, RouteClose.panel);
    expect(RouteHandle.of('/nowhere').floating, true);
  });

  testWidgets('the AED card shows place, access, entrance and the route action', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [aedsProvider.overrideWith(_ReadyAeds.new)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: DefiSheetScroll(child: AedDetailsPanel(id: '7')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Urząd Dzielnicy'), findsOneWidget);
    expect(find.text('Dostęp całodobowy'), findsOneWidget);
    expect(find.text('Wejście główne, recepcja'), findsOneWidget);
    expect(find.text('Wewnątrz budynku, parter'), findsOneWidget);
    expect(find.text('Wyznacz trasę'), findsOneWidget);

    await tester.tap(find.text('Godziny dostępu'));
    await tester.pumpAndSettle();
    expect(find.text('Całodobowo, 7 dni w tygodniu'), findsOneWidget);
  });
}
