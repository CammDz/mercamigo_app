import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/admin_product.dart';
import '../../repositories/admin_catalog_repository.dart';
import '../../services/product_image_service.dart';
import '../widgets/figma_header.dart';

/// Administración sencilla de promociones y sus banners.
class AdminPromotionsScreen extends StatefulWidget {
  const AdminPromotionsScreen({super.key});

  static const String routeName = '/admin/promotions';

  @override
  State<AdminPromotionsScreen> createState() => _AdminPromotionsScreenState();
}

class _AdminPromotionsScreenState extends State<AdminPromotionsScreen> {
  final _name = TextEditingController();
  final _packageQty = TextEditingController(text: '3');
  final _packagePrice = TextEditingController();
  List<AdminProduct> _products = <AdminProduct>[];
  List<Map<String, dynamic>> _promotions = <Map<String, dynamic>>[];
  final Set<String> _selected = <String>{};
  String _type = 'dos_por_uno';
  String? _bannerUrl;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _packageQty.dispose();
    _packagePrice.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final AdminCatalogRepository repo = context
          .read<AdminCatalogRepository>();
      final results = await Future.wait<Object>(<Future<Object>>[
        repo.load(),
        repo.loadPromotions(),
      ]);
      if (!mounted) return;
      setState(() {
        _products = (results[0] as AdminCatalogSnapshot).products
            .where((AdminProduct p) => p.isActive)
            .toList();
        _promotions = results[1] as List<Map<String, dynamic>>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _message('No se pudieron cargar las promociones: $error');
    }
  }

  Future<void> _pickBanner() async {
    try {
      final String? url = await context
          .read<ProductImageService>()
          .pickAndUpload(source: ImageSource.gallery, productId: 'promociones');
      if (url != null && mounted) setState(() => _bannerUrl = url);
    } catch (error) {
      _message('$error');
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final int qty = int.tryParse(_packageQty.text.trim()) ?? 3;
      await context.read<AdminCatalogRepository>().savePromotion(
        name: _name.text.trim().isEmpty ? _label : _name.text.trim(),
        type: _type,
        buyQuantity: _type == 'tres_por_dos' ? 3 : 2,
        freeQuantity: _type == 'dos_por_uno'
            ? 1
            : (_type == 'tres_por_dos' ? 1 : 0),
        packageQuantity: qty.clamp(2, 100),
        packagePrice:
            int.tryParse(_packagePrice.text.replaceAll('.', '').trim()) ?? 0,
        bannerUrl: _bannerUrl,
        productIds: _selected.toList(),
      );
      if (!mounted) return;
      _selected.clear();
      _name.clear();
      _bannerUrl = null;
      _message('Promoción guardada.');
      await _load();
    } catch (error) {
      _message('$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _label {
    switch (_type) {
      case 'tres_por_dos':
        return '3x2';
      case 'precio_paquete':
        return '${_packageQty.text} por paquete';
      default:
        return '2x1';
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: FigmaHeader(
        title: 'Promociones',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
              children: <Widget>[
                _section('Crear promoción'),
                const SizedBox(height: 12),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Nombre (opcional)',
                    hintText: 'Ej. Oferta de la semana',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de promoción',
                  ),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem(value: 'dos_por_uno', child: Text('2x1')),
                    DropdownMenuItem(value: 'tres_por_dos', child: Text('3x2')),
                    DropdownMenuItem(
                      value: 'precio_paquete',
                      child: Text('Paquete a precio fijo'),
                    ),
                  ],
                  onChanged: (String? value) =>
                      setState(() => _type = value ?? 'dos_por_uno'),
                ),
                if (_type == 'precio_paquete') ...<Widget>[
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _packageQty,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Unidades del paquete',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _packagePrice,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Precio total COP',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),
                _section('Productos incluidos'),
                const SizedBox(height: 4),
                if (_products.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No hay productos activos.'),
                  )
                else
                  ..._products.map(
                    (AdminProduct product) => CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _selected.contains(product.id),
                      title: Text(
                        product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('\$${product.price} COP'),
                      onChanged: (bool? checked) => setState(() {
                        if (checked == true) {
                          _selected.add(product.id);
                        } else {
                          _selected.remove(product.id);
                        }
                      }),
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _pickBanner,
                  icon: const Icon(Icons.image_outlined),
                  label: Text(
                    _bannerUrl == null
                        ? 'Elegir imagen del banner'
                        : 'Cambiar imagen del banner',
                  ),
                ),
                if (_bannerUrl != null) ...<Widget>[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      _bannerUrl!,
                      height: 130,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _saving || _selected.isEmpty ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: const Text('Guardar promoción'),
                ),
                const SizedBox(height: 26),
                _section('Promociones activas'),
                const SizedBox(height: 10),
                if (_promotions.isEmpty)
                  const Text('Todavía no hay promociones configuradas.')
                else
                  ..._promotions.map(_promotionCard),
              ],
            ),
    );
  }

  Widget _section(String title) => Text(
    title,
    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
  );

  Widget _promotionCard(Map<String, dynamic> promo) {
    final String id = promo['id'] as String? ?? '';
    final bool active = promo['activa'] as bool? ?? false;
    final String title = promo['nombre'] as String? ?? 'Promoción';
    final List<dynamic> linked =
        promo['productos'] as List<dynamic>? ?? <dynamic>[];
    final String products = linked
        .map((dynamic x) => (x as Map<String, dynamic>)['producto'])
        .whereType<Map<String, dynamic>>()
        .map((Map<String, dynamic> x) => x['nombre'] as String? ?? '')
        .join(', ');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.local_offer_outlined)),
        title: Text(title),
        subtitle: Text(
          products.isEmpty ? 'Sin productos' : products,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Switch(
          value: active,
          onChanged: (bool value) async {
            try {
              await context.read<AdminCatalogRepository>().setPromotionActive(
                id,
                value,
              );
              await _load();
            } catch (error) {
              _message('$error');
            }
          },
        ),
      ),
    );
  }
}
