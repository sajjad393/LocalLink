import 'package:flutter_bloc/flutter_bloc.dart';
import '../domain/directory_models.dart';
import '../domain/directory_repository_contract.dart';
class ContactsBloc extends Cubit<List<DirectoryProfile>> {
  final DirectoryRepositoryContract repository;
  ContactsBloc(this.repository):super(const []);
  Future<void> load() async {emit(await repository.contacts());}
  Future<void> remove(String id) async {await repository.removeContact(id); await load();}
  Future<void> block(String id) async {await repository.blockUser(id); await load();}
}
