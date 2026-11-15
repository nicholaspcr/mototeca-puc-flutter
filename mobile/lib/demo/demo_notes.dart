part of 'demo_backend.dart';

/// The owners' maintenance notes, with the same rules as the Go API.
extension _Notes on DemoBackend {
  Map<String, dynamic> _addNote(Map<String, dynamic> request, String? token) {
    final ownerId = _ownerId(token);
    final clientId = request['clientId'] as String? ?? '';
    final existing = _notes
        .where((n) => n['ownerId'] == ownerId && n['clientId'] == clientId)
        .firstOrNull;
    if (existing != null) return {'note': _noteJson(existing)};

    final plate = normalizePlate(request['plate'] as String? ?? '');
    final vehicle = _vehicles
        .where((v) => v['plate'] == plate && v['ownerId'] == ownerId)
        .firstOrNull;
    if (vehicle == null) {
      throw DemoFailure(
        404,
        'not_found',
        'esta moto não está vinculada a você',
      );
    }
    _requireText(request['description'], 'descreva o que foi feito');
    final doneOn = DateTime.tryParse(request['doneOn'] as String? ?? '');
    if (doneOn == null) {
      throw DemoFailure(400, 'invalid_argument', 'data inválida');
    }
    if (doneOn.isAfter(DateTime.now().add(const Duration(days: 1)))) {
      throw DemoFailure(
        400,
        'invalid_argument',
        'a data não pode estar no futuro',
      );
    }

    final note = {
      'id': _id('note'),
      'vehicleId': vehicle['id'],
      'ownerId': ownerId,
      'clientId': clientId,
      'doneOn': formatDay(doneOn),
      'description': (request['description'] as String).trim(),
      'mileageKm': request['mileageKm'],
      'costCents': request['costCents'],
      'photoUrl': null,
    };
    _notes.add(note);
    return {'note': _noteJson(note)};
  }

  Map<String, dynamic> _deleteNote(
    Map<String, dynamic> request,
    String? token,
  ) {
    final note = _ownedNote(request['id'] as String? ?? '', _ownerId(token));
    _notes.remove(note);
    return {};
  }

  /// Only the author, and only while they still own the bike.
  Map<String, dynamic> _ownedNote(String id, String ownerId) {
    final note = _notes
        .where((n) => n['id'] == id && n['ownerId'] == ownerId)
        .firstOrNull;
    final stillOwned = _vehicles.any(
      (v) => v['id'] == note?['vehicleId'] && v['ownerId'] == ownerId,
    );
    if (note == null || !stillOwned) {
      throw DemoFailure(404, 'not_found', 'anotação não encontrada');
    }
    return note;
  }

  List<Map<String, dynamic>> _notesJson(String vehicleId) {
    final notes = _notes.where((n) => n['vehicleId'] == vehicleId).toList()
      ..sort(
        (a, b) => (b['doneOn'] as String).compareTo(a['doneOn'] as String),
      );
    return notes.map(_noteJson).toList();
  }

  Map<String, dynamic> _noteJson(Map<String, dynamic> n) => {
    'id': n['id'],
    'doneOn': n['doneOn'],
    'description': n['description'],
    'mileageKm': ?n['mileageKm'],
    'costCents': ?n['costCents'],
    'photoUrl': ?n['photoUrl'],
  };
}
