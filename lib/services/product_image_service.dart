import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Errores de la subida de la foto del producto.
///
/// SeTranslatean a mensajes claros para la persona que administra.
class ProductImageException implements Exception {
  const ProductImageException(this.message);

  /// Mensaje para mostrar en pantalla.
  final String message;

  @override
  String toString() => message;
}

/// Sube la foto de un producto a Supabase Storage.
///
/// La foto se guarda en el bucket `producto-imagenes` con la ruta
/// `productos/{producto_id}/{timestamp}.jpg`. Al reemplazar una foto se
/// borra la anterior del mismo bucket para no acumular copias.
class ProductImageService {
  ProductImageService({required this.client, ImagePicker? picker})
      : picker = picker ?? ImagePicker();

  /// Bucket donde se guardan las fotos de los productos.
  static const String bucket = 'producto-imagenes';

  /// Cliente de Supabase (para Storage).
  ///
  /// Es `null` si la app se compiló sin servidor: entonces no se pueden
  /// subir fotos.
  final SupabaseClient? client;

  /// Selector de imágenes de Android/iOS.
  final ImagePicker picker;

  /// Lado máximo (en píxeles) de la foto subida.
  static const int maxSide = 1280;

  /// Calidad de la imagen subida (JPEG).
  static const int quality = 82;

  /// Elige una foto del celular y la sube.
  ///
  /// Devuelve `null` si la persona cancela la selección.
  Future<String?> pickAndUpload({
    required ImageSource source,
    required String productId,
    String? currentImageUrl,
  }) async {
    final XFile? file = await _pick(source);
    if (file == null) return null;
    return upload(
      file: file,
      productId: productId,
      currentImageUrl: currentImageUrl,
    );
  }

  /// Elige una foto del celular (sin subirla todavía).
  ///
  /// Se usa cuando el producto todavía no existe: la foto se sube cuando se
  /// crea, para poder guardarla con el identificador real del producto.
  Future<XFile?> pick(ImageSource source) => _pick(source);

  /// Sube una foto ya elegida al bucket y devuelve su dirección pública.
  Future<String> upload({
    required XFile file,
    required String productId,
    String? currentImageUrl,
  }) async {
    final SupabaseClient? supabase = client;
    if (supabase == null) {
      throw const ProductImageException(
        'El servidor no está configurado en esta compilación: no se pueden '
        'subir fotos.',
      );
    }
    final String folder = productId.trim().isEmpty ? 'sin-identificar' : productId.trim();
    final String path =
        'productos/$folder/${DateTime.now().millisecondsSinceEpoch}.jpg';

    try {
      final Uint8List bytes = await file.readAsBytes();
      await supabase.storage.from(bucket).uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(
          contentType: 'image/jpeg',
          upsert: false,
        ),
      );
    } on StorageException catch (error) {
      throw ProductImageException(_friendlyStorageMessage(error));
    } catch (error) {
      throw ProductImageException('No se pudo subir la foto: $error');
    }

    final String url = supabase.storage.from(bucket).getPublicUrl(path);

    // La foto anterior se borra: no se acumulan copias.
    await _deleteIfOwned(currentImageUrl);

    return url;
  }

  /// Borra una foto anterior que esté en nuestro bucket.
  Future<void> deleteIfOwned(String? imageUrl) => _deleteIfOwned(imageUrl);

  Future<XFile?> _pick(ImageSource source) async {
    try {
      return await picker.pickImage(
        source: source,
        maxWidth: maxSide.toDouble(),
        maxHeight: maxSide.toDouble(),
        imageQuality: quality,
      );
    } catch (error) {
      final String text = error.toString();
      if (text.contains('permission') || text.contains('denied')) {
        throw const ProductImageException(
          'La app no tiene permiso para usar la cámara o la galería. '
          'Actívalo en los ajustes del teléfono.',
        );
      }
      throw ProductImageException('No se pudo abrir la galería: $error');
    }
  }

  Future<void> _deleteIfOwned(String? imageUrl) async {
    if (imageUrl == null || imageUrl.trim().isEmpty) return;
    final String marker = '/storage/v1/object/public/$bucket/';
    final int index = imageUrl.indexOf(marker);
    if (index < 0) return;
    final String path =
        Uri.decodeComponent(imageUrl.substring(index + marker.length));
    if (path.isEmpty) return;
    try {
      await client?.storage.from(bucket).remove(<String>[path]);
    } catch (_) {
      // Si no se puede borrar, la foto nueva ya está guardada: no se
      // interrumpe el flujo por eso.
    }
  }

  String _friendlyStorageMessage(StorageException error) {
    final String message = error.message.trim();
    if (message.toLowerCase().contains('row-level security') ||
        message.toLowerCase().contains('policy')) {
      return 'Tu cuenta no tiene permiso para subir fotos al catálogo.';
    }
    if (message.toLowerCase().contains('not exist') ||
        message.toLowerCase().contains('bucket')) {
      return 'No se encontró el bucket de fotos ($bucket).';
    }
    if (message.isEmpty) {
      return 'No se pudo subir la foto al servidor.';
    }
    return 'No se pudo subir la foto: $message';
  }
}
