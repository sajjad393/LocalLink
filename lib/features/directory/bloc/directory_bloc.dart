import 'package:flutter_bloc/flutter_bloc.dart';
import '../domain/directory_models.dart';
import '../domain/directory_repository_contract.dart';
abstract class DirectoryEvent { const DirectoryEvent(); }
class SearchDirectoryByPhone extends DirectoryEvent { final String phone; const SearchDirectoryByPhone(this.phone); }
class SearchDirectoryByName extends DirectoryEvent { final String query; const SearchDirectoryByName(this.query); }
class LoadDirectoryProfile extends DirectoryEvent { final String userId; const LoadDirectoryProfile(this.userId); }
class SyncDirectory extends DirectoryEvent { const SyncDirectory(); }
abstract class DirectoryState { const DirectoryState(); }
class DirectoryInitial extends DirectoryState { const DirectoryInitial(); }
class DirectoryLoading extends DirectoryState { const DirectoryLoading(); }
class DirectoryResults extends DirectoryState { final List<DirectoryProfile> profiles; const DirectoryResults(this.profiles); }
class DirectoryProfileLoaded extends DirectoryState { final DirectoryProfile? profile; const DirectoryProfileLoaded(this.profile); }
class DirectoryError extends DirectoryState { final String message; const DirectoryError(this.message); }
class DirectoryBloc extends Bloc<DirectoryEvent, DirectoryState> {
  final DirectoryRepositoryContract repository;
  DirectoryBloc(this.repository):super(const DirectoryInitial()) {
    on<SearchDirectoryByPhone>((e,emit) async {emit(const DirectoryLoading()); try {final p=await repository.findByPhone(e.phone); emit(DirectoryResults(p==null?const[]:[p]));} catch(x){emit(DirectoryError(x.toString().replaceFirst('Exception: ','')));}});
    on<SearchDirectoryByName>((e,emit) async {emit(const DirectoryLoading()); try {emit(DirectoryResults(await repository.searchByName(e.query)));} catch(x){emit(DirectoryError(x.toString().replaceFirst('Exception: ','')));}});
    on<LoadDirectoryProfile>((e,emit) async {emit(const DirectoryLoading()); try {emit(DirectoryProfileLoaded(await repository.getProfile(e.userId)));} catch(x){emit(DirectoryError(x.toString().replaceFirst('Exception: ','')));}});
    on<SyncDirectory>((e,emit) async {emit(const DirectoryLoading()); try {await repository.sync(); emit(const DirectoryResults([]));} catch(x){emit(DirectoryError(x.toString().replaceFirst('Exception: ','')));}});
  }
}
