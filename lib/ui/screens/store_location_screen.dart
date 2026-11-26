import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/store_location.dart';
import '../../services/location_service.dart';
import '../../state/store_location_controller.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/primary_button.dart';
import '../widgets/store_map.dart';

/// Pantalla de ubicación de la tienda para el **comprador**.
///
/// Es una pantalla de **solo consulta**: muestra el nombre, la dirección y la
/// ubicación guardada y permite abrir "Cómo llegar". No hay botones de
/// editar ni de guardar, y el marcador de la tienda no se puede arrastrar:
/// tocar el mapa no cambia las coordenadas guardadas y mover o ampliar el
/// mapa solo cambia la vista.
///
/// La posición del cliente (su GPS) se puede mostrar como un punto
/// informativo: representa dónde está el usuario y **nunca** sustituye la
/// ubicación de la tienda.
class StoreLocationScreen extends StatefulWidget {
  const StoreLocationScreen({super.key});

  static const String routeName = '/store-location';

  @override
  State<StoreLocationScreen> createState() => _StoreLocationScreenState();
}

class _StoreLocationScreenState extends State<StoreLocationScreen> {
  bool _requestingLocation = false;

  Future<void> _openDirections() async {
    final StoreLocationController controller = context
        .read<StoreLocationController>();
    final bool opened = await controller.openDirections();
    if (!mounted) return;
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se encontró una aplicación de mapas disponible.'),
        ),
      );
    }
  }

  Future<void> _showMyPosition() async {
    final StoreLocationController controller = context
        .read<StoreLocationController>();
    setState(() => _requestingLocation = true);
    final LocationResult result = await controller.requestUserLocation();
    if (!mounted) return;
    setState(() => _requestingLocation = false);
    if (!result.isSuccess) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.errorMessage)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Tu posición se muestra en el mapa. La ubicación de la tienda no '
          'cambia.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final StoreLocationController controller = context
        .watch<StoreLocationController>();
    final StoreLocation location = controller.location;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppTopBar(
        title: 'Ubicación de la tienda',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double maxWidth = constraints.maxWidth >= 600 ? 620 : 460;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (!controller.isLoaded)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else ...<Widget>[
                        _StatusCard(
                          configured: controller.isConfigured,
                          name: location.name,
                          address: location.address,
                        ),
                        const SizedBox(height: 18),
                        StoreMap(
                          latitude: location.latitude,
                          longitude: location.longitude,
                          userLatitude: controller.userLatitude,
                          userLongitude: controller.userLongitude,
                        ),
                        const SizedBox(height: 14),
                        if (location.latitude != null &&
                            location.longitude != null)
                          Text(
                            'Coordenadas: ${location.latitude}, '
                            '${location.longitude}',
                            textAlign: TextAlign.center,
                            style: AppText.body(12.5, color: AppColors.muted),
                          ),
                        const SizedBox(height: 16),
                        PrimaryButton(
                          label: 'Cómo llegar',
                          icon: Icons.directions_outlined,
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.ink,
                          outlined: true,
                          onPressed: controller.isConfigured
                              ? _openDirections
                              : null,
                        ),
                        const SizedBox(height: 10),
                        PrimaryButton.outlined(
                          label: _requestingLocation
                              ? 'Obteniendo ubicación...'
                              : 'Mostrar mi posición',
                          icon: Icons.my_location,
                          isLoading: _requestingLocation,
                          onPressed: _requestingLocation
                              ? null
                              : _showMyPosition,
                        ),
                        if (!controller.isConfigured) ...<Widget>[
                          const SizedBox(height: 10),
                          Text(
                            'La tienda todavía no tiene una ubicación '
                            'configurada.',
                            textAlign: TextAlign.center,
                            style: AppText.body(13, color: AppColors.muted),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Text(
                          'La compra funciona sin permiso de ubicación: solo se '
                          'pide cuando usas "Mostrar mi posición".',
                          textAlign: TextAlign.center,
                          style: AppText.body(12, color: AppColors.muted),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Tarjeta con el estado de la configuración de la tienda.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.configured, this.name, this.address});

  final bool configured;
  final String? name;
  final String? address;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: configured ? const Color(0xFFEAF1FC) : const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: configured ? AppColors.primary : AppColors.warning,
          width: 1.3,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            configured ? Icons.storefront : Icons.location_off_outlined,
            color: configured ? AppColors.primary : AppColors.warning,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  configured
                      ? (name?.isNotEmpty == true ? name! : 'Mercamigo')
                      : StoreLocation.pendingMessage,
                  style: AppText.body(
                    16,
                    weight: FontWeight.w700,
                    color: configured ? AppColors.ink : AppColors.warning,
                  ),
                ),
                if (configured && address != null && address!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    address!,
                    style: AppText.body(14, color: AppColors.muted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
