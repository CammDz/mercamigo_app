import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mercamigo_app/data/local/key_value_store.dart';
import 'package:mercamigo_app/repositories/cart_repository.dart';
import 'package:mercamigo_app/repositories/catalog_repository.dart';
import 'package:mercamigo_app/services/auth_service.dart';
import 'package:mercamigo_app/services/supabase_service.dart';
import 'package:mercamigo_app/state/cart_controller.dart';
import 'package:mercamigo_app/state/catalog_controller.dart';
import 'package:mercamigo_app/state/origin_controller.dart';
import 'package:mercamigo_app/ui/screens/catalog_screen.dart';
import 'package:mercamigo_app/ui/widgets/app_search_field.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import 'helpers/catalog_fixtures.dart';

/// La búsqueda del catálogo se hace **en la misma pantalla**: no se abre
/// ninguna otra ruta, y se buscan productos de todo el catálogo.
void main() {
  Future<CatalogRepository> repository() =>
      CatalogFixtures.buildRepository(store: InMemoryStore());

  Future<CatalogRepository> repositoryWithThreePromotions() async {
    final InMemoryStore store = InMemoryStore();
    final CatalogRepository catalogRepository =
        await CatalogFixtures.buildRepository(store: store);
    final Map<String, dynamic> cached = jsonDecode(
      (await store.readString('mercamigo.catalog.cache'))!,
    ) as Map<String, dynamic>;
    final List<dynamic> products = cached['products'] as List<dynamic>;
    for (int index = 0; index < 3; index++) {
      (products[index]
          as Map<String, dynamic>)['promotion'] = <String, dynamic>{
        'id': 'promo-$index',
        'title': 'Promo ${index + 1}',
        'type': 'twoForOne',
        'description': 'Oferta de prueba',
        'bundleQuantity': 2,
      };
    }
    await store.writeString('mercamigo.catalog.cache', jsonEncode(cached));
    await catalogRepository.refresh();
    return catalogRepository;
  }

  Widget app(CatalogRepository catalogRepository) {
    final CartRepository cart = CartRepository(InMemoryStore());
    return MultiProvider(
      providers: <SingleChildWidget>[
        Provider<SupabaseService>.value(
          value: const SupabaseService(
            client: null,
            status: SupabaseStatus.disabled,
          ),
        ),
        ChangeNotifierProvider<AuthService>.value(value: AuthService(null)),
        Provider<CatalogRepository>.value(value: catalogRepository),
        ChangeNotifierProvider<CatalogController>(
          create: (_) =>
              CatalogController(catalogRepository: catalogRepository),
        ),
        ChangeNotifierProvider<CartController>(
          create: (_) => CartController(
            cartRepository: cart,
            catalogRepository: catalogRepository,
          ),
        ),
        ChangeNotifierProvider<OriginController>(
          create: (_) => OriginController(cartRepository: cart),
        ),
      ],
      child: const MaterialApp(home: CatalogScreen()),
    );
  }

  testWidgets('Escribir en la barra no abre otra pantalla', (
    WidgetTester tester,
  ) async {
    final CatalogRepository catalogRepository = await repository();
    await tester.pumpWidget(app(catalogRepository));
    await tester.pump();

    final NavigatorState navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    expect(find.text('Categorias'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'astra');
    await tester.pumpAndSettle();

    // No se ha abierto ninguna ruta nueva.
    expect(navigator.canPop(), isFalse);
    expect(find.byType(CatalogScreen), findsOneWidget);
  });

  testWidgets('Los resultados se ven en la misma pantalla', (
    WidgetTester tester,
  ) async {
    final CatalogRepository catalogRepository = await repository();
    await tester.pumpWidget(app(catalogRepository));
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'astra');
    await tester.pumpAndSettle();

    // El contenido del catálogo se sustituye por los resultados.
    expect(find.text('Categorias'), findsNothing);
    expect(find.textContaining('Buscando en todo el catálogo'), findsOneWidget);
    expect(find.textContaining('Astra'), findsWidgets);
  });

  testWidgets('La búsqueda ignora mayúsculas y tildes', (
    WidgetTester tester,
  ) async {
    final CatalogRepository catalogRepository = await repository();
    await tester.pumpWidget(app(catalogRepository));
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'ASTRÁ');
    await tester.pumpAndSettle();

    expect(find.textContaining('Astra'), findsWidgets);
  });

  testWidgets('Con más de dos promociones el banner rota automáticamente', (
    WidgetTester tester,
  ) async {
    final CatalogRepository catalogRepository =
        await repositoryWithThreePromotions();
    await tester.pumpWidget(app(catalogRepository));
    await tester.pump();

    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('Promo 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Promoción 1 de 3'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Promo 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Promoción 2 de 3'), findsOneWidget);
  });

  testWidgets('Si no hay coincidencias se avisa, sin error', (
    WidgetTester tester,
  ) async {
    final CatalogRepository catalogRepository = await repository();
    await tester.pumpWidget(app(catalogRepository));
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'zzz-no-existe');
    await tester.pumpAndSettle();

    expect(find.text('Sin resultados'), findsOneWidget);
    expect(
      find.textContaining('No encontramos productos para'),
      findsOneWidget,
    );
  });

  testWidgets('La X limpia el texto y restaura el catálogo', (
    WidgetTester tester,
  ) async {
    final CatalogRepository catalogRepository = await repository();
    await tester.pumpWidget(app(catalogRepository));
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'astra');
    await tester.pumpAndSettle();
    expect(find.text('Categorias'), findsNothing);

    // La X del campo de búsqueda.
    await tester.tap(
      find.descendant(
        of: find.byType(AppSearchField),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Categorias'), findsOneWidget);
    expect(find.text('Sin resultados'), findsNothing);
  });

  testWidgets('Un texto vacío no muestra error ni abre pantalla', (
    WidgetTester tester,
  ) async {
    final CatalogRepository catalogRepository = await repository();
    await tester.pumpWidget(app(catalogRepository));
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pumpAndSettle();

    expect(find.text('Categorias'), findsOneWidget);
    expect(find.text('Sin resultados'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
