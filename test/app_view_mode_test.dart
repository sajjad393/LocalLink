import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/state/app_view_mode.dart';

void main() {
  test('view mode defaults to user and admin entry requires capability', () {
    final cubit = AppViewModeCubit();
    addTearDown(cubit.close);

    expect(cubit.state.mode, AppViewMode.user);
    expect(cubit.state.adminCapable, isFalse);
    expect(cubit.state.serverConnected, isFalse);
    expect(cubit.enterAdminView(), isFalse);
    expect(cubit.state.mode, AppViewMode.user);
  });

  test('admin-capable account can switch admin -> user -> admin', () {
    final cubit = AppViewModeCubit();
    addTearDown(cubit.close);

    cubit.setAdminCapability(true);
    expect(cubit.enterAdminView(), isFalse);
    cubit.setServerConnected(true);
    expect(cubit.enterAdminView(), isTrue);
    expect(cubit.state.mode, AppViewMode.admin);

    cubit.enterUserView();
    expect(cubit.state.mode, AppViewMode.user);
    expect(cubit.state.adminCapable, isTrue);

    expect(cubit.enterAdminView(), isTrue);
    expect(cubit.state.mode, AppViewMode.admin);

    cubit.enterUserView();
    cubit.setServerConnected(false);
    cubit.setServerConnected(true);
    expect(cubit.state.mode, AppViewMode.user);
    expect(cubit.state.adminCapable, isTrue);
  });

  test('revoking admin capability forces safe user view', () {
    final cubit = AppViewModeCubit();
    addTearDown(cubit.close);

    cubit.setAdminCapability(true);
    cubit.setServerConnected(true);
    expect(cubit.enterAdminView(), isTrue);
    cubit.setAdminCapability(false);

    expect(cubit.state.adminCapable, isFalse);
    expect(cubit.state.mode, AppViewMode.user);
  });

  test('reset clears admin capability and mode', () {
    final cubit = AppViewModeCubit();
    addTearDown(cubit.close);

    cubit.setAdminCapability(true);
    cubit.setServerConnected(true);
    cubit.enterAdminView();
    cubit.reset();

    expect(cubit.state, const AppViewModeState());
  });
  test('server disconnect forces an active admin view back to user view', () {
    final cubit = AppViewModeCubit();
    addTearDown(cubit.close);

    cubit.setAdminCapability(true);
    cubit.setServerConnected(true);
    expect(cubit.enterAdminView(), isTrue);

    cubit.setServerConnected(false);
    expect(cubit.state.mode, AppViewMode.user);
    expect(cubit.state.adminCapable, isTrue);
    expect(cubit.canEnterAdminView, isFalse);
  });

}
