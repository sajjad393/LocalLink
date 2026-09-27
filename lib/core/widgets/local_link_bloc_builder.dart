import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Small composition wrapper used when a screen owns a feature BLoC directly.
/// The actual rebuild is performed by the flutter_bloc BlocBuilder.
class LocalLinkBlocBuilder<B extends StateStreamable<S>, S> extends StatelessWidget {
  final B bloc;
  final Widget Function(BuildContext context, S state) builder;

  const LocalLinkBlocBuilder({super.key, required this.bloc, required this.builder});

  @override
  Widget build(BuildContext context) => BlocBuilder<B, S>(bloc: bloc, builder: builder);
}
