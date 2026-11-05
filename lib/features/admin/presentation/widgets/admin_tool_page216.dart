import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';

/// Bundle 216 (E): one shell for every server tool page — the 216 app bar,
/// pull to refresh, and the live lock (216d) when the server is lost.
/// Reads [AdminBloc] and [AppViewModeCubit] from the context (the panel's
/// `_openModule` provides both).
class AdminToolPage216 extends StatefulWidget {
  const AdminToolPage216({
    super.key,
    required this.title,
    required this.module,
    required this.builder,
    this.subtitle,
    this.right,
    this.withDashboard = false,
  });

  /// Also load the dashboard reads (health, analytics) once on open.
  final bool withDashboard;

  final String title;

  /// The panel module key ('Users', 'Network & Mesh', …) for logs.
  final String module;
  final String? Function(AdminState state)? subtitle;
  final Widget? right;
  final List<Widget> Function(BuildContext context, AdminState state) builder;

  @override
  State<AdminToolPage216> createState() => _AdminToolPage216State();
}

class _AdminToolPage216State extends State<AdminToolPage216> {
  @override
  void initState() {
    super.initState();
    if (widget.withDashboard) {
      final bloc = context.read<AdminBloc>();
      scheduleMicrotask(() => bloc.loadDashboard(range: '24h').catchError((_) {}));
    }
  }

  Future<void> _reload(AdminBloc bloc) async {
    await bloc.load();
    if (widget.withDashboard) await bloc.loadDashboard(range: '24h');
  }

  static AppViewModeCubit? _viewOf(BuildContext context) {
    try {
      return context.read<AppViewModeCubit>();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<AdminBloc>();
    final view = _viewOf(context);
    return BlocBuilder<AdminBloc, AdminState>(
      builder: (context, state) => AdminPage216(
        title: widget.title,
        subtitle: widget.subtitle?.call(state),
        right: widget.right,
        module: widget.module,
        needsServer: view != null,
        viewMode: view,
        onServerBack: () => _reload(bloc),
        onRefresh: () => _reload(bloc),
        children: [
          const SizedBox(height: 2),
          if (state.error != null && !state.loading)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AdminBanner216(A216BannerKind.warning, 'Some data could not load',
                  key: const ValueKey('a216_load_error'), body: state.error),
            ),
          ...widget.builder(context, state),
        ],
      ),
    );
  }
}

/// Spinner shown while a page has no data yet.
class AdminLoading216 extends StatelessWidget {
  const AdminLoading216({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
            child: SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      );
}
