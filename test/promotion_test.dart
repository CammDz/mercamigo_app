import 'package:flutter_test/flutter_test.dart';
import 'package:mercamigo_app/data/models/promotion.dart';

void main() {
  group('Reglas de promoción', () {
    test('2x1: se cobran ceil(cantidad / 2) unidades', () {
      const Promotion promo = DemoPromotionCatalog.astraTwoForOne;

      expect(promo.payableAmount(1, 2800), 2800);
      expect(promo.payableAmount(2, 2800), 2800);
      expect(promo.payableAmount(3, 2800), 5600);
      expect(promo.payableAmount(4, 2800), 5600);
      expect(promo.payableAmount(5, 2800), 8400);
    });

    test('2x1: el ahorro se calcula sobre el precio bruto', () {
      const Promotion promo = DemoPromotionCatalog.astraTwoForOne;

      expect(promo.savings(1, 2800), 0);
      expect(promo.savings(2, 2800), 2800);
      expect(promo.savings(3, 2800), 2800);
    });

    test('3x2: se cobran dos unidades completas por cada tres', () {
      const Promotion promo = Promotion(
        id: 'TEST-3X2',
        title: '3x2',
        type: PromotionType.threeForTwo,
        description: 'Prueba 3x2',
        bundleQuantity: 3,
      );

      expect(promo.payableAmount(1, 2000), 2000);
      expect(promo.payableAmount(2, 2000), 4000);
      expect(promo.payableAmount(3, 2000), 4000);
      expect(promo.payableAmount(4, 2000), 6000);
      expect(promo.payableAmount(6, 2000), 8000);
      expect(promo.savings(3, 2000), 2000);
    });

    test(r'3x$6.500: cada grupo de 3 tiene precio fijo', () {
      const Promotion promo = DemoPromotionCatalog.aguaThreeForSixFive;

      expect(promo.payableAmount(1, 3000), 3000);
      expect(promo.payableAmount(2, 3000), 6000);
      expect(promo.payableAmount(3, 3000), 6500);
      expect(promo.payableAmount(4, 3000), 9500);
      expect(promo.payableAmount(6, 3000), 13000);
    });

    test('una promoción nunca produce un ahorro negativo', () {
      const Promotion promo = DemoPromotionCatalog.aguaThreeForSixFive;
      expect(promo.savings(1, 3000), 0);
      expect(promo.savings(3, 3000), 2500);
    });

    test('las promociones se localizan por id', () {
      expect(DemoPromotions.byId('PROMO-ASTRA-2X1')?.title, '2x1');
      expect(DemoPromotions.byId('PROMO-NO-EXISTE'), isNull);
      expect(DemoPromotions.byId(null), isNull);
    });
  });
}
