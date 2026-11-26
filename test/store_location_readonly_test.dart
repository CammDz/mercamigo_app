import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mercamigo_app/data/local/key_value_store.dart';
import 'package:mercamigo_app/repositories/settings_repository.dart';
import 'package:mercamigo_app/state/store_location_controller.dart';
import 'package:mercamigo_app/ui/screens/store_location_screen.dart';
import 'package:mercamigo_app/ui/widgets/store_map.dart';
import 'package:provider/provider.dart';

void main() {
  Future<StoreLocationController> controllerWith(
    Map<String, String> store,
  ) async {
    final SettingsRepository settings = SettingsRepository(
      store: InMemoryStore(store),
    );
    final StoreLocationController controller =
        StoreLocationController(settingsRepository: settings);
    await controller.load();
    return controller;
  }

  group('La ubicación de la tienda es de solo consulta para el comprador', () {
    testWidgets('No muestra botones de editar ni de guardar',
        (WidgetTester tester) async {
      final StoreLocationController controller = await controllerWith(
        <String, String>{
          'mercamigo.settings.store':
              '{"id":null,"name":"Mercamigo Centro","address":"Calle 10 # 20-30",'
                  '"latitude":4.710989,"longitude":-74.072092,"isActive":true,'
                  '"isFromServer":false}',
        },
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<StoreLocationController>.value(
          value: controller,
          child: const MaterialApp(home: StoreLocationScreen()),
        ),
      );
      await tester.pump();

      // Se muestra la información de la tienda...
      expect(find.text('Mercamigo Centro'), findsOneWidget);
      expect(find.text('Calle 10 # 20-30'), findsOneWidget);
      expect(find.text('Cómo llegar'), findsOneWidget);

      // ...pero no hay ninguna acción de edición.
      expect(find.text('Guardar configuración'), findsNothing);
      expect(find.text('Guardar cambios'), findsNothing);
      expect(find.text('Nombre de la tienda'), findsNothing);
      expect(find.text('Dirección'), findsNothing);
      expect(find.text('Latitud'), findsNothing);
      expect(find.text('Longitud'), findsNothing);
    });

    testWidgets('El GPS del cliente no sustituye las coordenadas guardadas',
        (WidgetTester tester) async {
      final StoreLocationController controller = await controllerWith(
        <String, String>{
          'mercamigo.settings.store':
              '{"id":null,"name":"Mercamigo Centro","address":"Calle 10 # 20-30",'
                  '"latitude":4.710989,"longitude":-74.072092,"isActive":true,'
                  '"isFromServer":false}',
        },
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<StoreLocationController>.value(
          value: controller,
          child: const MaterialApp(home: StoreLocationScreen()),
        ),
      );
      await tester.pump();

      // La ubicación de la tienda sigue siendo la guardada.
      expect(controller.location.latitude, 4.710989);
      expect(controller.location.longitude, -74.072092);

      // Y el botón del cliente solo muestra su posición: no guarda nada.
      expect(find.text('Mostrar mi posición'), findsOneWidget);
      expect(find.text('Usar mi ubicación (borrador)'), findsNothing);
    });
  });

  group('El mapa no cambia la ubicación guardada', () {
    testWidgets('Mover el mapa no altera las coordenadas (solo consulta)',
        (WidgetTester tester) async {
      LatLng? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StoreMap(
              latitude: 4.710989,
              longitude: -74.072092,
              onPick: (LatLng point) => picked = point,
            ),
          ),
        ),
      );
      await tester.pump();

      // Un gesto de arrastre sobre el mapa no debe elegir ningún punto.
      await tester.drag(find.byType(StoreMap), const Offset(-120, 60));
      await tester.pumpAndSettle();

      expect(picked, isNull);
    });

    testWidgets('En modo edición tocar el mapa elige un punto',
        (WidgetTester tester) async {
      LatLng? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StoreMap(
              latitude: 4.710989,
              longitude: -74.072092,
              onPick: (LatLng point) => picked = point,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tapAt(tester.getCenter(find.byType(StoreMap)));
      // flutter_map confirma el toque tras el retardo anti doble toque.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(picked, isNotNull);
    });

    testWidgets('El mapa muestra la tienda y la posición del cliente',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StoreMap(
              latitude: 4.710989,
              longitude: -74.072092,
              userLatitude: 4.712000,
              userLongitude: -74.071000,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Dos marcas: la tienda (principal) y el cliente (punto azul).
      final MarkerLayer layer = tester.widget<MarkerLayer>(
        find.byType(MarkerLayer),
      );
      expect(layer.markers, hasLength(2));
      expect(layer.markers.any((Marker m) => m.point.latitude == 4.712000), isTrue);
      expect(
        layer.markers.any((Marker m) => m.point.latitude == 4.710989),
        isTrue,
      );
    });
  });
}
