import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/money.dart';
import '../../data/models/admin_product.dart';
import '../../repositories/admin_catalog_repository.dart';
import '../../services/camera_permission_service.dart';
import '../../services/product_image_service.dart';
import '../widgets/figma_header.dart';
import '../widgets/primary_button.dart';
import '../widgets/product_barcode.dart';

/// Formulario de producto: alta o edición.
///
/// En **alta** el servidor crea el producto y **genera su código principal**
/// automáticamente; el formulario no pide ni inventa códigos. Al terminar se
/// muestra el código asignado para que el administrador lo conozca.
///
/// En **edición** solo se modifican los datos: el código principal es de solo
/// lectura y no se regenera. Los códigos adicionales se gestionan en la
/// pantalla de códigos.
class AdminProductFormScreen extends StatefulWidget {
  const AdminProductFormScreen({super.key, this.product});

  static const String routeName = '/admin/producto';

  /// `null` = alta. Con valor = edición.
  final AdminProduct? product;

  @override
  State<AdminProductFormScreen> createState() => _AdminProductFormScreenState();
}

class _AdminProductFormScreenState extends State<AdminProductFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _imageController = TextEditingController();

  List<AdminCategory> _categories = const <AdminCategory>[];
  String? _categoryId;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  /// Foto elegida en el celular que todavía no se ha subido.
  XFile? _pendingPhoto;

  /// `true` cuando ya se guardó: no hay que pedir confirmación al salir.
  bool _saved = false;

  /// Valores iniciales, para detectar cambios sin guardar.
  late final String _initialName = widget.product?.name ?? '';
  late final String _initialDescription = widget.product?.description ?? '';
  late final String _initialPrice = '${widget.product?.price ?? ''}';
  late final String? _initialCategory = widget.product?.categoryId;

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final AdminProduct? product = widget.product;
    if (product != null) {
      _nameController.text = product.name;
      _descriptionController.text = product.description;
      _priceController.text = '${product.price}';
      _imageController.text = product.imageUrl ?? '';
      _categoryId = product.categoryId;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCategories());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  /// `true` si hay cambios que se perderían al salir.
  bool get _hasChanges {
    if (_saved) return false;
    return _nameController.text != _initialName ||
        _descriptionController.text != _initialDescription ||
        _priceController.text != _initialPrice ||
        _categoryId != _initialCategory ||
        _pendingPhoto != null;
  }

  /// Pide confirmación si hay cambios sin guardar.
  Future<void> _confirmExit() async {
    if (_busy) return;
    if (!_hasChanges) {
      Navigator.of(context).maybePop();
      return;
    }
    final bool discard =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: const Text('¿Descartar cambios?'),
            content: const Text(
              'Los datos que escribiste no se han guardado. '
              'Si sales ahora se perderán.',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Seguir editando'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                child: const Text('Descartar'),
              ),
            ],
          ),
        ) ??
        false;
    if (discard && mounted) {
      _saved = true;
      Navigator.of(context).pop(false);
    }
  }

  Future<void> _loadCategories() async {
    final AdminCatalogRepository repository = context
        .read<AdminCatalogRepository>();
    try {
      final AdminCatalogSnapshot snapshot = await repository.load();
      if (!mounted) return;
      setState(() {
        _categories = snapshot.categories
            .where((AdminCategory c) => c.isActive)
            .toList(growable: false);
        _categoryId ??= _categories.isEmpty ? null : _categories.first.id;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar las categorías: $error';
        _loading = false;
      });
    }
  }

  /// Elige una foto del celular (cámara o galería).
  ///
  /// La foto **no** se sube todavía: se sube al guardar el producto, cuando
  /// ya se conoce su identificador (para editarla y para crearla).
  Future<void> _pickPhoto() async {
    final ImageSource? source = await _askSource();
    if (source == null || !mounted) return;

    // Para tomar la foto hace falta el permiso de camara: la app lo declara
    // (tambien lo usa el escaner), asi que hay que concederlo antes.
    if (source == ImageSource.camera) {
      final CameraPermissionService permissions =
          const CameraPermissionService();
      CameraPermissionStatus status = await permissions.status();
      if (status != CameraPermissionStatus.granted) {
        status = await permissions.request();
      }
      if (status != CameraPermissionStatus.granted && mounted) {
        setState(() {
          _error =
              'Activa el permiso de la camara para tomar la foto, o '
              'elige una imagen de la galeria.';
        });
        return;
      }
    }

    if (!mounted) return;
    final ProductImageService service = context.read<ProductImageService>();
    try {
      final XFile? file = await service.pick(source);
      if (file == null || !mounted) return;
      setState(() {
        _pendingPhoto = file;
        _error = null;
      });
    } on ProductImageException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo elegir la foto: $error');
    }
  }

  /// Pregunta de dónde sacar la foto.
  Future<ImageSource?> _askSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 8),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.grayBorder,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              ListTile(
                leading: const Icon(
                  Icons.photo_camera_outlined,
                  color: AppColors.primary,
                ),
                title: Text('Tomar foto', style: AppText.body(16)),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_outlined,
                  color: AppColors.primary,
                ),
                title: Text('Elegir de la galería', style: AppText.body(16)),
                onTap: () =>
                    Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  /// Descarta la foto elegida pero todavía no subida.
  void _clearPhoto() {
    setState(() => _pendingPhoto = null);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final int? price = int.tryParse(_priceController.text.trim());
    if (price == null || price <= 0) {
      setState(() => _error = 'El precio debe ser un número mayor que cero.');
      return;
    }
    final String? categoryId = _categoryId;
    if (categoryId == null) {
      setState(() => _error = 'Elige una categoría.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final AdminCatalogRepository repository = context
        .read<AdminCatalogRepository>();
    final ProductImageService images = context.read<ProductImageService>();
    try {
      final String name = _nameController.text.trim();
      final String description = _descriptionController.text.trim();
      final String? currentImage = _imageController.text.trim().isEmpty
          ? null
          : _imageController.text.trim();
      final XFile? photo = _pendingPhoto;

      if (_isEdit) {
        final String id = widget.product!.id;
        String? imageUrl = currentImage;
        if (photo != null) {
          // El producto ya existe: la foto se sube con su identificador.
          imageUrl = await images.upload(
            file: photo,
            productId: id,
            currentImageUrl: currentImage,
          );
        }
        await repository.editProduct(
          id: id,
          name: name,
          description: description,
          categoryId: categoryId,
          price: price,
          imageUrl: imageUrl,
        );
      } else {
        // El servidor genera el código principal: aquí no se envía ninguno.
        final CreatedProduct? created = await repository.createProduct(
          categoryId: categoryId,
          name: name,
          description: description,
          price: price,
          imageUrl: currentImage,
        );
        if (created == null) {
          throw const AdminCatalogException(
            'El servidor no devolvió el producto creado.',
          );
        }

        String? uploadWarning;
        if (photo != null) {
          // El producto recién creado ya tiene identificador: la foto se
          // guarda en su carpeta y se actualiza el producto.
          try {
            final String imageUrl = await images.upload(
              file: photo,
              productId: created.id,
            );
            await repository.editProduct(
              id: created.id,
              name: name,
              description: description,
              categoryId: categoryId,
              price: price,
              imageUrl: imageUrl,
            );
          } on Exception catch (error) {
            uploadWarning =
                'El producto se creó, pero la foto no se pudo subir: $error';
          }
        }

        if (!mounted) return;
        _saved = true;
        setState(() => _pendingPhoto = null);
        await _showCreatedCode(created.code, warning: uploadWarning);
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      if (!mounted) return;
      _saved = true;
      setState(() => _pendingPhoto = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEdit ? 'Producto actualizado.' : 'Producto creado.'),
        ),
      );
      Navigator.of(context).pop(true);
    } on ProductImageException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } on AdminCatalogException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo guardar el producto: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Muestra el código que generó el servidor al crear el producto.
  Future<void> _showCreatedCode(String code, {String? warning}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Producto creado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'El servidor le asignó este código de barras principal:',
            ),
            const SizedBox(height: 12),
            SelectableText(
              code,
              style: AppText.body(
                22,
                weight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Es único y no se modifica al editar el producto.',
              style: AppText.body(12.5, color: AppColors.muted),
            ),
            if (warning != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(warning, style: AppText.body(12.5, color: AppColors.danger)),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_hasChanges || _saved,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        _confirmExit();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: FigmaHeader(
          title: _isEdit ? 'Editar producto' : 'Crear producto',
          onBack: _confirmExit,
        ),
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
                      const _FieldLabel('Nombre del producto'),
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: _fieldDecoration(
                          'Astra-Cola Original 500 ml',
                        ),
                        validator: (String? value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'El nombre es obligatorio.'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      const _FieldLabel('Descripción'),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: _fieldDecoration(
                          'Bebida gaseosa · Botella de 500 ml',
                        ),
                      ),
                      const SizedBox(height: 14),
                      const _FieldLabel('Categoría'),
                      DropdownButtonFormField<String>(
                        initialValue: _categoryId,
                        decoration: _fieldDecoration('Elige una categoría'),
                        items: _categories
                            .map(
                              (AdminCategory category) =>
                                  DropdownMenuItem<String>(
                                    value: category.id,
                                    child: Text(category.name),
                                  ),
                            )
                            .toList(),
                        onChanged: (String? value) =>
                            setState(() => _categoryId = value),
                        validator: (String? value) =>
                            value == null ? 'Elige una categoría.' : null,
                      ),
                      const SizedBox(height: 14),
                      const _FieldLabel('Precio en COP'),
                      TextFormField(
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: _fieldDecoration('\$3,000'),
                        validator: (String? value) {
                          final int? parsed = int.tryParse(
                            (value ?? '').trim(),
                          );
                          if (parsed == null || parsed <= 0) {
                            return 'El precio debe ser mayor que cero.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      const _FieldLabel('Imagen del producto'),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: _PhotoField(
                          imageUrl: _imageController.text.trim(),
                          localFile: _pendingPhoto,
                          busy: _busy,
                          onPick: _pickPhoto,
                          onClear: _clearPhoto,
                        ),
                      ),
                      if (_isEdit &&
                          widget.product!.codes.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 16),
                        _ProductVariablesCard(product: widget.product!),
                      ],
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.lilac,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _isEdit
                              ? 'El código de barras lo generó el servidor y no '
                                    'cambia al editar el producto.'
                              : 'El código de barras se genera automáticamente '
                                    'al crear el producto.',
                          style: AppText.body(
                            12.5,
                            color: AppColors.textDark,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      PrimaryButton(
                        label: _isEdit ? 'Guardar cambios' : 'Crear producto',
                        isLoading: _busy,
                        onPressed: _busy ? null : _save,
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
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

/// Etiqueta pequeña encima de cada campo del formulario.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: AppText.body(12.5, weight: FontWeight.w600)),
    );
  }
}

/// Código de barras y variables del producto en la vista de edición.
///
/// El código principal lo generó el servidor: se muestra dibujado con su
/// número y no se puede editar ni regenerar desde aquí.
class _ProductVariablesCard extends StatelessWidget {
  const _ProductVariablesCard({required this.product});

  final AdminProduct product;

  @override
  Widget build(BuildContext context) {
    final String code = product.codes.first.code;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Variables del producto',
            style: AppText.body(
              13,
              weight: FontWeight.w700,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 10),
          ProductBarcode(code: code, height: 78),
          const SizedBox(height: 12),
          _VariableRow(label: 'Categoría', value: product.categoryName),
          _VariableRow(label: 'Precio', value: formatCop(product.price)),
          _VariableRow(
            label: 'Estado',
            value: product.isActive ? 'Activo' : 'Inactivo',
          ),
          const SizedBox(height: 4),
          Text(
            'El código de barras no se modifica al editar el producto.',
            style: AppText.body(12, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

/// Fila de una variable del producto.
class _VariableRow extends StatelessWidget {
  const _VariableRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 92,
            child: Text(label, style: AppText.body(13, color: AppColors.muted)),
          ),
          Expanded(
            child: Text(
              value,
              style: AppText.body(
                13.5,
                weight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Foto del producto: la que se sube desde el celular.
///
/// Muestra la vista previa (la foto recién elegida o la que ya está en el
/// servidor) y el botón para cambiarla.
class _PhotoField extends StatelessWidget {
  const _PhotoField({
    required this.imageUrl,
    required this.localFile,
    required this.busy,
    required this.onPick,
    required this.onClear,
  });

  /// Dirección de la foto que ya tiene el producto (puede estar vacía).
  final String imageUrl;

  /// Foto elegida en el celular que todavía no se ha subido.
  final XFile? localFile;

  /// `true` mientras se guarda el producto.
  final bool busy;

  /// Pide la foto.
  final VoidCallback onPick;

  /// Descarta la foto elegida.
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final bool remote = imageUrl.startsWith('http');
    final bool hasImage = localFile != null || remote;

    return Row(
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(width: 54, height: 54, child: _preview(remote)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              InkWell(
                onTap: busy ? null : onPick,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    hasImage ? 'Seleccionar otra imagen' : 'Seleccionar imagen',
                    style: AppText.body(12.5, weight: FontWeight.w700),
                  ),
                ),
              ),
              if (localFile != null)
                InkWell(
                  onTap: busy ? null : onClear,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      'Quitar imagen',
                      style: AppText.body(11.5, color: AppColors.textMuted),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _preview(bool remote) {
    final XFile? file = localFile;
    if (file != null) {
      return Image.file(
        File(file.path),
        width: 96,
        height: 96,
        fit: BoxFit.cover,
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
            _placeholder(),
      );
    }
    if (remote) {
      return Image.network(
        imageUrl,
        width: 96,
        height: 96,
        fit: BoxFit.cover,
        loadingBuilder:
            (BuildContext context, Widget child, ImageChunkEvent? progress) {
              if (progress == null) return child;
              return _placeholder();
            },
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
            _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.surfaceSoft,
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, size: 34, color: AppColors.muted),
    );
  }
}
