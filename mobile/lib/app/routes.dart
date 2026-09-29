/// Route names — mirrors design/NAVIGATION.md. `/` is a home screen in both
/// apps, never a login; [signIn] is an ordinary route pushed on top.
class Routes {
  /// Shared by both apps.
  static const home = '/';
  static const signIn = '/entrar';
  static const signUp = '/cadastro';
  static const plateLookup = '/consulta';
  static const serviceDetail = '/servico';
  static const vehicleRegister = '/veiculo/cadastro';
  static const about = '/sobre';

  /// App Motociclista.
  static const garage = '/garagem';
  static const reminders = '/lembretes';

  /// App Oficina.
  static const dashboard = '/painel';
  static const newRecord = '/registro/novo';
  static const reviseRecord = '/registro/corrigir';
  static const outbox = '/fila';
}
