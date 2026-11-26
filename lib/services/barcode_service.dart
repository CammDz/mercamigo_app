import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Comparte la imagen de un código de barras.
///
/// La imagen se escribe en la carpeta temporal de la app (no hace falta
/// permiso de almacenamiento) y se abre la hoja nativa de compartir.
class BarcodeShareService {
  const BarcodeShareService._();

  /// Comparte la imagen del código.
  static Future<ShareResultStatus> shareBarcode({
    required Uint8List bytes,
    required String code,
  }) async {
    if (bytes.isEmpty) {
      throw StateError('La imagen del código quedó vacía.');
    }

    final Directory directory = await getTemporaryDirectory();
    final String safeCode = code.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '_');
    final File file = File('${directory.path}/codigo-$safeCode.png');
    await file.writeAsBytes(bytes, flush: true);

    if (!await file.exists() || await file.length() == 0) {
      throw StateError('No se pudo preparar la imagen del código.');
    }

    final ShareResult result = await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile(file.path, mimeType: 'image/png', name: 'codigo-$safeCode.png'),
        ],
        text: 'Código de barras $code · Mercamigo',
        subject: 'Código de barras - Mercamigo',
        title: 'Compartir código de barras',
      ),
    );
    return result.status;
  }
}
