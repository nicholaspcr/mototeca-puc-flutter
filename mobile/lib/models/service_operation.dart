/// The fixed operation taxonomy (ARCHITECTURE.md section 3).
///
/// [wire] is the protobuf enum name the API speaks; [label] is what the
/// mechanic reads on the chips. Keeping both on one enum means the two can
/// never drift apart in separate lists.
enum ServiceOperation {
  oilChange('SERVICE_TYPE_OIL_CHANGE', 'Troca de óleo e filtro'),
  scheduledReview('SERVICE_TYPE_SCHEDULED_REVIEW', 'Revisão programada'),
  brakes('SERVICE_TYPE_BRAKES', 'Freios (pastilhas, discos, fluido)'),
  chainAndSprocket(
    'SERVICE_TYPE_CHAIN_AND_SPROCKET',
    'Corrente, relação e coroa',
  ),
  tires('SERVICE_TYPE_TIRES', 'Pneus'),
  electrical('SERVICE_TYPE_ELECTRICAL', 'Elétrica / bateria'),
  sparkPlugs('SERVICE_TYPE_SPARK_PLUGS', 'Velas / ignição'),
  suspension('SERVICE_TYPE_SUSPENSION', 'Suspensão'),
  clutch('SERVICE_TYPE_CLUTCH', 'Embreagem'),
  fuelInjection(
    'SERVICE_TYPE_FUEL_INJECTION',
    'Carburação / injeção eletrônica',
  ),
  bodywork('SERVICE_TYPE_BODYWORK', 'Funilaria / pintura'),
  other('SERVICE_TYPE_OTHER', 'Outro');

  const ServiceOperation(this.wire, this.label);

  final String wire;
  final String label;

  /// Returns null for an unknown value so a record added by a newer server
  /// version degrades to "one operation we don't render" instead of crashing.
  static ServiceOperation? fromWire(String? wire) {
    for (final operation in values) {
      if (operation.wire == wire) return operation;
    }
    return null;
  }

  static List<ServiceOperation> listFromWire(List<dynamic>? raw) =>
      (raw ?? const [])
          .map((value) => fromWire(value as String?))
          .whereType<ServiceOperation>()
          .toList();
}
