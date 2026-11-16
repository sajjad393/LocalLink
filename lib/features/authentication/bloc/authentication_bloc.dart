import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/core/crypto/password_kdf.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/features/authentication/domain/login_problem_321.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 110: submit() outcome — either a server-authenticated session or a
/// silent offline reopen of a locally known account. No message is emitted on
/// either success path.
final class AuthOutcome {
  final AuthResult? result;
  final bool offline;

  const AuthOutcome.offline({this.madeOffline = false, this.problem})
      : result = null,
        offline = true;

  const AuthOutcome.online(this.result)
      : offline = false,
        madeOffline = false,
        problem = null;

  /// Bundle 321 (L2 / L-13): why the server was not used when the saved
  /// account was opened (null = not known). Home tells it once.
  final LoginProblem321? problem;

  /// Bundle 256 A4: a NEW phone-only account was made because no server
  /// answered - the screen says so once ("Saved on this phone").
  final bool madeOffline;

  bool get online => result != null;
}

final class AuthenticationState extends Equatable {
  final bool registerMode;
  final bool busy;
  final String? error;

  /// Bundle 102: the last submit failed because no server was reachable —
  /// the register screen may now offer the offline account path.
  final bool offlineRegisterAvailable;

  /// Bundle 256 A4: what the screen shows under the button while busy:
  /// 'search' = looking for the server, 'found' = server found. Null = none.
  final String? stage;

  /// Bundle 321 (L3): the server address shown in the step line
  /// ("Server found · 192.168.18.27 · signing in…"). '' = none.
  final String server;

  /// Bundle 321 (L1): the code line under the button, e.g.
  /// "Code L-02a · 192.168.18.27". Null = none.
  final String? code;

  const AuthenticationState({
    this.registerMode = false,
    this.busy = false,
    this.error,
    this.offlineRegisterAvailable = false,
    this.stage,
    this.server = '',
    this.code,
  });

  AuthenticationState copyWith({
    bool? registerMode,
    bool? busy,
    String? error,
    bool clearError = false,
    bool? offlineRegisterAvailable,
    String? stage,
    bool clearStage = false,
    String? server,
    String? code,
  }) {
    return AuthenticationState(
      registerMode: registerMode ?? this.registerMode,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
      offlineRegisterAvailable:
          offlineRegisterAvailable ?? this.offlineRegisterAvailable,
      stage: clearStage ? null : (stage ?? this.stage),
      server: clearStage ? '' : (server ?? this.server),
      // Bundle 321: the code goes with the error it belongs to.
      code: clearError ? null : (code ?? this.code),
    );
  }

  @override
  List<Object?> get props =>
      [registerMode, busy, error, offlineRegisterAvailable, stage, server, code];
}

final class AuthenticationBloc extends Cubit<AuthenticationState> {
  final AuthenticationRepositoryContract repository;

  AuthenticationBloc(
    this.repository, {
    bool registerMode = false,
  }) : super(AuthenticationState(registerMode: registerMode));

  bool get registerMode => state.registerMode;
  bool get busy => state.busy;
  String? get error => state.error;

  void clearError() {
    if (state.error != null) emit(state.copyWith(clearError: true));
  }

  Future<AuthOutcome> submit({
    required String username,
    required String password,
  }) async {
    final user = username.trim().toLowerCase();
    if (user.isEmpty || password.isEmpty) {
      throw _validation(L.t.enterYourUsernameAndPassword);
    }
    if (!RegExp(r'^[a-z0-9_][a-z0-9_.-]{2,31}$').hasMatch(user)) {
      throw _validation(
        L.t.usernameMustBe332Characters,
      );
    }
    if (state.registerMode && password.length < 8) {
      throw _validation(L.t.passwordMustBeAtLeast8);
    }

    final what = state.registerMode ? 'create' : 'sign_in';
    emit(state.copyWith(busy: true, clearError: true, stage: 'search'));
    var serverFound = false;
    final started = DateTime.now();
    int ms() => DateTime.now().difference(started).inMilliseconds;
    try {
      final deviceName = repository.generateUniqueDeviceName();
      await repository.prepareForAuthentication(deviceName: deviceName);
      serverFound = true;
      emit(state.copyWith(stage: 'found', server: LoginProblem321.hostOf(_serverAddress())));
      if (state.registerMode) {
        final result = await repository.register(
          username: user,
          password: password,
          deviceName: deviceName,
        );
        await _mirror(user, password, result);
        await repository.completeOfflineLogin(); // clears any prior sign-out gate
        AppLogger.info('AUTH_RESULT', detail: 'what=$what mode=server ms=${ms()}');
        return AuthOutcome.online(result);
      }
      final result = await repository.login(
        username: user,
        password: password,
        deviceName: deviceName,
      );
      await _mirror(user, password, result);
      await repository.completeOfflineLogin();
      AppLogger.info('AUTH_RESULT', detail: 'what=$what mode=server ms=${ms()}');
      return AuthOutcome.online(result);
    } catch (error) {
      final stage = serverFound ? 'login' : 'verify';
      // Bundle 321 (L1 / L7 / L14): the code comes from the error TYPE,
      // the HTTP status and the server's error code. A bare StateError
      // from the search step = "no server found" (older repositories).
      final LoginProblem321? problem;
      if (error is ServerProblem256) {
        problem = const LoginProblem321('L-06');
      } else if (error is StateError && !serverFound) {
        problem = null;
      } else {
        problem = LoginProblem321.of(error,
            stage: stage, address: serverFound ? _serverAddress() : '');
      }
      // Bundle 256 A5: offline ONLY when no server answered.
      final offlineOk = problem == null ? true : problem.noServer;
      if (offlineOk) {
        final reason = serverFound ? 'server_lost' : 'no_server';
        // Bundle 110: server-first → offline fallback.
        final offline = await _offlineFallback(user, password, problem);
        if (offline != null) {
          AppLogger.info('AUTH_RESULT',
              detail: 'what=$what mode=offline reason=$reason code=${problem?.code ?? 'L-01'} '
                  'stage=$stage ms=${ms()}');
          return offline;
        }
      }
      final shown = problem ?? const LoginProblem321('L-01');
      AppLogger.info('AUTH_RESULT',
          detail: 'what=$what mode=none reason=${error is ServerProblem256 ? 'server_problem' : 'error'} '
              'code=${shown.code} status=${shown.status} err=${error.runtimeType} stage=$stage ms=${ms()}');
      emit(state.copyWith(
        // Bundle 256: a server problem is shown as it is.
        error: error is ServerProblem256 ? error.message : shown.words,
        code: shown.codeLine,
        offlineRegisterAvailable: false,
      ));
      rethrow;
    } finally {
      emit(state.copyWith(busy: false, clearStage: true));
    }
  }

  /// Bundle 110: after an ONLINE success, mirror the credentials into secure
  /// storage so the account can be reopened later without any server. A
  /// mirror failure never fails the login itself.
  Future<void> _mirror(String user, String password, AuthResult result) async {
    try {
      await repository.mirrorOfflineLogin(
        username: user,
        password: password,
        recoveryCode: result.recoveryCode,
      );
    } catch (_) {}
  }

  /// Silent offline path (Bundle 110). Registering while offline creates a
  /// fully local account; logging in reopens a locally known account via its
  /// password, or via its recovery code typed in the password field.
  Future<AuthOutcome?> _offlineFallback(
      String user, String password, LoginProblem321? problem) async {
    if (state.registerMode) {
      if (password.length < 8) {
        throw _validation(L.t.passwordMustBeAtLeast8);
      }
      await repository.registerOffline(username: user, password: password);
      await repository.completeOfflineLogin();
      return AuthOutcome.offline(madeOffline: true, problem: problem);
    }
    // Bundle 223 (J): the password check runs off the screen thread.
    // Bundle 278: with the reason, so a phone with nothing saved does not
    // say "do not match".
    final repo = repository;
    String? reason278;
    final bool byPassword;
    if (repo is OfflineLoginReason278) {
      reason278 = await (repo as OfflineLoginReason278).offlineLoginReason278(user, password);
      byPassword = reason278 == 'ok';
    } else {
      byPassword = repo is AsyncOfflineLogin
          ? await (repo as AsyncOfflineLogin).verifyOfflineLoginAsync(user, password)
          : repository.verifyOfflineLogin(user, password);
    }
    if (byPassword || repository.verifyOfflineRecovery(user, password)) {
      // Bundle 214 (G6): log line only (no behaviour change).
      AppLogger.info('AUTH_OFFLINE_LOGIN',
          detail: 'ok via=${byPassword ? 'password' : 'recovery'}');
      await repository.completeOfflineLogin();
      // Bundle 123: self-heal accounts created before offline registration
      // seeded a profile — pairing read LocalStore.profile() and found null.
      await repository.ensureOfflineProfileSeed();
      return AuthOutcome.offline(problem: problem ?? const LoginProblem321('L-01'));
    }
    // Known receiver: the credential simply did not match — say so plainly,
    // with a single fixed message and no connectivity chatter.
    // Bundle 278: the words say why (nothing saved / another account /
    // wrong password); the log has the reason, never a name.
    final why278 = reason278 ?? 'bad_password';
    AppLogger.info('AUTH_OFFLINE_LOGIN', detail: 'bad reason=$why278');
    // Bundle 321 (L13 / L14): the server reason comes first, then what
    // the phone could (not) open - never "turn the server on" / "do not
    // match" alone when it was the server that failed.
    final text278 = problem == null
        ? offlineLoginText278(why278)
        : '${problem.words} ${offlineAfterServerText321(why278)}';
    emit(state.copyWith(error: text278, code: problem?.codeLine));
    throw Exception(text278);
  }

  /// Register without a reachable server (Bundle 102). Returns the recovery
  /// code to display once; the account publishes later when the configured
  /// server answers.
  Future<String> registerOffline({
    required String username,
    required String password,
  }) async {
    final user = username.trim().toLowerCase();
    if (user.isEmpty || password.isEmpty) {
      throw _validation(L.t.enterYourUsernameAndPassword);
    }
    if (!RegExp(r'^[a-z0-9_][a-z0-9_.-]{2,31}$').hasMatch(user)) {
      throw _validation(
        L.t.usernameMustBe332Characters,
      );
    }
    if (password.length < 8) {
      throw _validation(L.t.passwordMustBeAtLeast8);
    }
    emit(state.copyWith(
        busy: true, clearError: true, offlineRegisterAvailable: false));
    try {
      final recovery = await repository.registerOffline(
          username: user, password: password);
      emit(state.copyWith(busy: false));
      return recovery;
    } catch (error) {
      emit(state.copyWith(busy: false, error: cleanBlocError(error)));
      rethrow;
    }
  }

  /// The saved server address ('' when none / a test double has none).
  String _serverAddress() {
    try {
      return repository.serverAddress ?? '';
    } catch (_) {
      return '';
    }
  }

  Exception _validation(String message) {
    emit(state.copyWith(error: message));
    return Exception(message);
  }
}
