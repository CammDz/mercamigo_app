import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/admin_product.dart';
import '../../repositories/admin_catalog_repository.dart';
import '../../state/store_location_controller.dart';
import '../widgets/figma_header.dart';
import '../widgets/store_map.dart';

/// Configuración de la tienda (solo administrador).
///
/// Los cambios se mantienen en un **borrador**: mover el marcador o tocar el
/// mapa NO escribe nada en la base de datos. Solo al pulsar "Guardar
/// cambios" se envía al servidor, y siempre sobre la tienda existente (por
/// su id), para no crear duplicados. "Cancelar" sale sin modificar nada.
class AdminStoreScreen extends StatefulWidget {
  const AdminStoreScreen({super.key});

  static const String routeName = '/admin/tienda';

  @override
  State<AdminStoreScreen> createState() => _AdminStoreScreenState();
}

class _AdminStoreScreenState extends State<AdminStoreScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();

  /// Identificador de la tienda que se está editando (si existe).
  String? _storeId;

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final AdminStore? store = await context
          .read<AdminCatalogRepository>()
          .loadStore();
      if (!mounted) return;
      setState(() {
        _storeId = store?.id;
        _nameController.text = store?.name ?? '';
        _addressController.text = store?.address ?? '';
        _latitudeController.text = store?.latitude == null
            ? ''
            : '${store!.latitude}';
        _longitudeController.text = store?.longitude == null
            ? ''
            : '${store!.longitude}';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar la tienda: $error';
        _loading = false;
      });
    }
  }

  double? get _draftLatitude =>
      double.tryParse(_latitudeController.text.trim());
  double? get _draftLongitude =>
      double.tryParse(_longitudeController.text.trim());

  /// Elige un punto en el mapa: solo cambia el borrador.
  void _pickPoint(LatLng point) {
    setState(() {
      _latitudeController.text = '${point.latitude}';
      _longitudeController.text = '${point.longitude}';
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final double? latitude = _draftLatitude;
    final double? longitude = _draftLongitude;
    if ((latitude == null) != (longitude == null)) {
      setState(() => _error = 'Latitud y longitud se configuran juntas.');
      return;
    }
    if (latitude != null &&
        (latitude < -90 ||
            latitude > 90 ||
            longitude! < -180 ||
            longitude > 180)) {
      setState(() => _error = 'Las coordenadas están fuera de rango.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });

    try {
      await context.read<AdminCatalogRepository>().saveStore(
        id: _storeId,
        name: _nameController.text.trim(),
        address: _addressController.text.trim(),
        latitude: latitude,
        longitude: longitude,
      );
      if (!mounted) return;
      // Se recarga la configuración efectiva para el comprador.
      await context.read<StoreLocationController>().load();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Cambios guardados.';
      });
    } on AdminCatalogException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'No se pudo guardar la tienda: $error';
      });
    }
  }

  void _cancel() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final double? latitude = _draftLatitude;
    final double? longitude = _draftLongitude;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: FigmaHeader(title: 'Configurar tienda', onBack: _cancel),
      body: SafeArea(
        top: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: <Widget>[
                    if (_error != null) ...<Widget>[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _error!,
                          style: AppText.body(13, color: AppColors.danger),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_message != null) ...<Widget>[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _message!,
                          style: AppText.body(13, color: AppColors.success),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    const _StoreLabel('Nombre de la tienda'),
                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: _storeDecoration('Mercamigo UTS'),
                      validator: (String? value) =>
                          (value == null || value.trim().isEmpty)
                          ? 'El nombre de la tienda es obligatorio.'
                          : null,
                    ),
                    const SizedBox(height: 14),
                    const _StoreLabel('Dirección'),
                    TextFormField(
                      controller: _addressController,
                      textCapitalization: TextCapitalization.words,
                      decoration: _storeDecoration('Av. Los Estudiantes #9-82'),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Ubicación de la tienda',
                            style: AppText.body(14.5, weight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: StoreMap(
                              latitude: latitude,
                              longitude: longitude,
                              onPick: _pickPoint,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            latitude == null || longitude == null
                                ? 'Sin ubicación configurada'
                                : '$latitude, $longitude',
                            style: AppText.body(
                              11.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Toca el mapa para ajustar la ubicación.',
                            style: AppText.body(
                              11.5,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.lilac,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Los cambios se aplicarán cuando pulses Guardar '
                        'cambios.',
                        style: AppText.body(
                          12,
                          color: AppColors.textDark,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 50,
                      child: FilledButton(
                        onPressed: _busy ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                'Guardar cambios',
                                style: AppText.body(
                                  14,
                                  weight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 50,
                      child: FilledButton(
                        onPressed: _busy ? null : _cancel,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.lilac,
                          foregroundColor: AppColors.textDark,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          'Cancelar',
                          style: AppText.body(14, weight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  InputDecoration _storeDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.cardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.cardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    );
  }
}

class _StoreLabel extends StatelessWidget {
  const _StoreLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: AppText.body(12.5, weight: FontWeight.w600)),
    );
  }
}
