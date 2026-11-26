import 'package:flutter_test/flutter_test.dart';
import 'package:mercamigo_app/data/models/product.dart';
import 'package:mercamigo_app/data/models/product_category.dart';

void main() {
  group('Códigos del producto', () {
    test('el tipo es siempre de barras', () {
      const ProductCode code = ProductCode(code: '0123456789012', type: 'barras');
      expect(code.isBarcode, isTrue);
      expect(code.type.trim().toLowerCase(), 'barras');
    });

    test('el código principal es el primero registrado', () {
      const Product product = Product(
        id: 'p1',
        name: 'Producto',
        description: '',
        categoryId: 'c1',
        category: ProductCategory(id: 'c1', name: 'General', isActive: true),
        price: 1000,
        stock: 5,
        isActive: true,
        isDemo: false,
        codes: <ProductCode>[
          ProductCode(code: '7890000000001', type: 'barras'),
          ProductCode(code: '7890000000002', type: 'barras'),
        ],
      );

      expect(product.codes.length, 2);
      expect(
        product.registeredCodes,
        <String>['7890000000001', '7890000000002'],
      );
      expect(product.registeredCode?.code, '7890000000001');
      expect(product.registeredCode?.isBarcode, isTrue);
      expect(product.hasRegisteredCode, isTrue);
    });

    test('la foto puede ser remota, local o ninguna', () {
      const Product base = Product(
        id: 'p1',
        name: 'Producto',
        description: '',
        categoryId: 'c1',
        category: ProductCategory(id: 'c1', name: 'General', isActive: true),
        price: 1000,
        stock: 5,
        isActive: true,
        isDemo: false,
      );
      expect(base.hasRemoteImage, isFalse);
      expect(base.localImageAsset, isNull);

      const Product remota = Product(
        id: 'p1',
        name: 'Producto',
        description: '',
        categoryId: 'c1',
        category: ProductCategory(id: 'c1', name: 'General', isActive: true),
        price: 1000,
        stock: 5,
        isActive: true,
        isDemo: false,
        imageUrl: 'https://proyecto.supabase.co/storage/v1/object/public/'
            'producto-imagenes/productos/p1/1.jpg',
      );
      expect(remota.hasRemoteImage, isTrue);
      expect(remota.localImageAsset, isNull);
    });
  });
}
