class Workshop {
  const Workshop({
    required this.id,
    required this.cnpj,
    required this.name,
    this.address,
    this.verified = false,
  });

  final String id;
  final String cnpj;
  final String name;
  final String? address;
  final bool verified;

  factory Workshop.fromJson(Map<String, dynamic> json) => Workshop(
    id: json['id'] as String? ?? '',
    cnpj: json['cnpj'] as String? ?? '',
    name: json['name'] as String? ?? '',
    address: json['address'] as String?,
    verified: json['verified'] as bool? ?? false,
  );
}

/// A workshop plus the session token issued with it.
class WorkshopSession {
  const WorkshopSession({required this.workshop, required this.token});

  final Workshop workshop;
  final String token;

  factory WorkshopSession.fromJson(Map<String, dynamic> json) =>
      WorkshopSession(
        workshop: Workshop.fromJson(
          json['workshop'] as Map<String, dynamic>? ?? const {},
        ),
        token: json['token'] as String? ?? '',
      );
}

/// Strips the punctuation people type into a CNPJ field.
String normalizeCnpj(String raw) => raw.replaceAll(RegExp(r'\D'), '');
