import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../domain/directory_models.dart';
import '../domain/directory_repository_contract.dart';

class ContactsBloc extends Cubit<List<DirectoryProfile>> {
  final DirectoryRepositoryContract repository;
  StreamSubscription<DirectoryProfile>? _updatesSub;

  ContactsBloc(this.repository) : super(const []) {
    // Bundle 125: the People tab stays mounted inside the home IndexedStack,
    // and this bloc previously loaded once and only refreshed on user
    // actions — a contact added by an incoming/outgoing pair stayed
    // invisible ("No contacts yet") until pull-to-refresh. Repaint on every
    // repository profile/contact update instead.
    _updatesSub = repository.profileUpdates.listen((_) => unawaited(load()));
  }

  Future<void> load() async {
    if (isClosed) return;
    final contacts = await repository.contacts();
    if (!isClosed) emit(contacts);
  }

  Future<void> remove(String id) async {
    await repository.removeContact(id);
    await load();
  }

  Future<void> block(String id) async {
    await repository.blockUser(id);
    await load();
  }

  /// Bundle 111: local-only rename; reload repaints rows, chats and search.
  Future<void> renameContact(String id, String customName) async {
    await repository.renameContact(id, customName);
    await load();
  }

  @override
  Future<void> close() async {
    await _updatesSub?.cancel();
    _updatesSub = null;
    return super.close();
  }
}
