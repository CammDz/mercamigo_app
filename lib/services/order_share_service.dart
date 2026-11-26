import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Compartir la orden como imagen PNG.
///
/// Se usa el mecanismo **nativo** de compartir (ACTION_SEND con un
/// FileProvider): el archivo vive en la carpeta temporal de la app, así que
/// no hace falta ningún permiso de almacenamiento.
class OrderShareService {
  const OrderShareService._();

  /// Escribe la imagen en un archivo temporal y abre la hoja de compartir.
  ///
  /// Devuelve el resultado de la hoja nativa. Lanza si la imagen está vacía
  /// o si no se puede escribir el archivo.
  static Future<ShareResultStatus> shareOrderImage({
    required Uint8List bytes,
    required String orderNumber,
    required String storeName,
  }) async {
    if (bytes.isEmpty) {
      throw StateError('La imagen de la orden quedó vacía.');
    }

    final Directory directory = await getTemporaryDirectory();
    // El nombre del archivo no lleva ningún token: solo el número visible.
    final String safeNumber = orderNumber.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '_');
    final File file = File('${directory.path}/orden-$safeNumber.png');
    await file.writeAsBytes(bytes, flush: true);

    if (!await file.exists() || await file.length() == 0) {
      throw StateError('No se pudo preparar la imagen de la orden.');
    }

    final ShareResult result = await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile(file.path, mimeType: 'image/png', name: 'orden-$safeNumber.png'),
        ],
        text: 'Orden $orderNumber · $storeName',
        subject: 'Orden $orderNumber - Mercamigo',
        title: 'Compartir orden',
      ),
    );
    return result.status;
  }
}
