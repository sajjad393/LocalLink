import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:flutter/foundation.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/admin/data/actions/admin_action_book.dart';
import 'package:locallink/features/admin/data/actions/admin_action_box.dart';
import 'package:locallink/features/admin/data/actions/admin_action_card.dart';
import 'package:locallink/features/admin/data/actions/admin_action_doers.dart';
import 'package:locallink/features/admin/data/actions/admin_action_server.dart';
import 'package:locallink/features/admin/data/actions/admin_action_store.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart'
    show AdminSignIn, ed25519Verify;

class _Entry {
  _Entry(this.id, this.action);
  final String id;
  String action;
  AdminActionCard? card; // null once stopped (only id + state + proof kept)
  String state = 'pending';
  int need = 0;
  bool mine = false;
  bool applied = false;
  String label = '';
  String madeAt = '';
  String updatedAt = '';
  SignedBlob? proof; // server state note or the cancel card
  Map<String, dynamic> extra = <String, dynamic>{};
  final Map<String, AdminActionDone> receipts = <String, AdminActionDone>{};
  final Set<String> counted = <String>{};

  bool get pending => state == 'pending';
  int get done => counted.length;
}

/// Bundle 220: every admin action goes to all phones.
///
/// * Cards travel to EVERY linked phone (friends or not) and the server.
/// * Only the target phone opens its box, does the action and sends back a
///   signed "done" receipt. Any phone carries receipts back.
/// * The stop: a server "state" note, receipts reaching `need`, or a cancel
///   card. Phones then keep only `{id, state, proof}` and answer anyone
///   still carrying the card with the proof ("no need to collect again").
/// * No time limit: a card stays Pending until done or cancelled.
class AdminActionService {
  AdminActionService({
    required this.store,
    required this.selfDeviceId,
    required this.selfUserId,
    required this.signingKey,
    required this.sign,
    required this.boxKeys,
    required this.send,
    required this.events,
    required this.linkedPeers,
    required this.serverKey,
    required this.endedCerts,
    required this.usableCert,
    required this.doers,
    this.adminSignIn,
    this.server,
    this.hints,
    this.serverOnline,
    this.viaOf,
    this.makeBlockInner,
    this.onChanged,
    this.build = AdminActionRules.appBuild,
    Future<bool> Function(String body, String sig, String key)? verify,
    DateTime Function()? clock,
    AdminActionBook? book,
  })  : verify = verify ?? ed25519Verify,
        _clock = clock ?? DateTime.now,
        book = book ?? AdminActionBook.instance;

  static AdminActionService? instance;

  final AdminActionStore store;
  final String Function() selfDeviceId;
  final String Function() selfUserId;
  final Future<String> Function() signingKey;
  final Future<String> Function(String body) sign;
  final Future<List<SimpleKeyPair>> Function() boxKeys;
  final Future<void> Function(String peerId, Map<String, dynamic> payload) send;
  final Stream<Map<String, dynamic>> events;
  final Future<List<String>> Function() linkedPeers;
  final String? Function() serverKey;
  final Set<String> Function() endedCerts;
  final Future<SignedBlob?> Function() usableCert;
  final AdminActionDoers doers;
  final Future<AdminSignIn?> Function()? adminSignIn;
  final AdminActionServer? server;

  /// Server push hints (`{"type":"admin_action"}` on the socket).
  final Stream<Map<String, dynamic>>? hints;
  final bool Function()? serverOnline;

  /// How a phone is linked: wifi | wifi_direct | mesh (for "Done via").
  final String Function(String peerId)? viaOf;

  /// Makes a signed 212 block / unblock card (Off / Active / Block offline).
  final Future<SignedBlob> Function(
      {required String userId,
      required List<String> devices,
      required String name,
      required bool block})? makeBlockInner;
  final void Function()? onChanged;
  final int build;
  final Future<bool> Function(String body, String sig, String key) verify;
  final DateTime Function() _clock;
  final AdminActionBook book;

  final Map<String, _Entry> _entries = <String, _Entry>{};
  final Map<String, AdminActionDone> _loose = <String, AdminActionDone>{};
  final Map<String, DateTime> _digestSentAt = <String, DateTime>{};
  final Set<String> _taking = <String>{}; // card ids being checked now
  final Set<String> _applying = <String>{}; // card ids being done now
  bool _loaded = false;
  bool _started = false;
  bool _syncBusy = false;
  StreamSubscription<Map<String, dynamic>>? _sub;
  StreamSubscription<Map<String, dynamic>>? _hintSub;
  Timer? _digestTimer;
  Timer? _serverTimer;
  Timer? _soon;

  // ------------------------------------------------------------------ load

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      for (final r in await store.actions()) {
        final id = r['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        final e = _Entry(id, r['action']?.toString() ?? '');
        final body = r['body']?.toString() ?? '';
        if (body.isNotEmpty) {
          e.card = AdminActionCard.fromBlob(
              SignedBlob(body: body, sig: r['sig']?.toString() ?? ''));
        }
        e.state = r['state']?.toString() ?? 'pending';
        e.need = _int(r['need']);
        e.mine = _int(r['mine']) == 1;
        e.applied = _int(r['applied']) == 1;
        e.label = r['label']?.toString() ?? '';
        e.madeAt = r['made_at']?.toString() ?? '';
        e.updatedAt = r['updated_at']?.toString() ?? '';
        e.proof = _blobOf(r['proof']);
        e.extra = _mapOf(r['extra']);
        _entries[id] = e;
      }
      for (final r in await store.receipts()) {
        final blob = SignedBlob(
            body: r['body']?.toString() ?? '', sig: r['sig']?.toString() ?? '');
        final d = AdminActionDone.fromBlob(blob);
        if (d == null) continue;
        final e = _entries[d.actionId];
        if (e == null) {
          _loose['${d.actionId}|${d.device}'] = d;
          continue;
        }
        e.receipts[d.device] = d;
        if (_int(r['counted']) == 1) e.counted.add(d.device);
      }
      AdminClosedFlag.closed.value =
          (await store.readSetting(AdminActionDoers.closedKey) ?? '') == '1';
    } catch (error) {
      AppLogger.warning('ADMIN_ACT_LOAD_FAIL', detail: '$error');
    }
    _publish();
  }

  void start() {
    if (_started) return;
    _started = true;
    instance = this;
    _sub = events.listen((e) => unawaited(handleEvent(e).catchError((_) {})));
    _hintSub = hints?.listen((m) {
      if (m['type']?.toString() == 'admin_action') syncSoon();
    });
    _digestTimer = Timer.periodic(AdminActionRules.digestEvery,
        (_) => unawaited(sendDigests().catchError((_) {})));
    _serverTimer = Timer.periodic(AdminActionRules.serverEvery,
        (_) => unawaited(syncWithServer().catchError((_) {})));
    unawaited(Future<void>.delayed(AdminActionRules.firstSync, () async {
      await load();
      await syncWithServer();
      await sendDigests();
      await _retryApply();
    }).catchError((_) {}));
  }

  Future<void> dispose() async {
    _digestTimer?.cancel();
    _serverTimer?.cancel();
    _soon?.cancel();
    await _sub?.cancel();
    await _hintSub?.cancel();
    _started = false;
    if (identical(instance, this)) instance = null;
  }

  void syncSoon() {
    _soon?.cancel();
    _soon = Timer(const Duration(seconds: 1),
        () => unawaited(syncWithServer().catchError((_) {})));
  }

  // ------------------------------------------------------------ the screen

  int get pendingMine =>
      _entries.values.where((e) => e.mine && e.pending && e.action != 'cancel').length;

  List<AdminActionRow> rows() {
    final out = <AdminActionRow>[];
    for (final e in _entries.values) {
      if (e.action == 'cancel') continue;
      if (!e.mine && e.label.isEmpty) continue; // only cards an admin made here / labelled
      final words = e.extra['words']?.toString() ?? '';
      final oldApp = e.extra['old_app'] == true;
      out.add(AdminActionRow(
        id: e.id,
        action: e.action,
        title: AdminActionRules.title(e.action, detail: words),
        name: e.label,
        sub: _subFor(e),
        state: e.state,
        done: e.done,
        need: e.need,
        oldApp: oldApp,
        offline: true,
        mine: e.mine,
        madeAt: e.madeAt,
        finishedAt: e.pending ? '' : e.updatedAt,
        via: e.receipts.values.map((r) => r.via).firstWhere((v) => v.isNotEmpty,
            orElse: () => ''),
      ));
    }
    out.sort((a, b) => b.madeAt.compareTo(a.madeAt));
    return out;
  }

  String _subFor(_Entry e) {
    if (e.state == 'cancelled') return 'Cancelled';
    if (e.state == 'replaced') return 'Replaced by a newer action';
    if (!e.pending) return e.need > 1 ? '${e.done} of ${e.need} phones' : 'Done';
    if (e.action == 'version_rule') return 'Reached ${e.done}';
    if (e.need > 1) return '${e.done} of ${e.need} phones';
    return 'Waiting for the phone';
  }

  void _publish() {
    book.set(rows());
    onChanged?.call();
  }

  // ------------------------------------------------------------- receiving

  Future<void> handleEvent(Map<String, dynamic> event) async {
    final type = event['type']?.toString();
    if (type == 'peer_connected') {
      final peer = event['peer_id']?.toString() ?? '';
      if (peer.isNotEmpty) {
        _digestSentAt.remove(peer); // a new meeting: always a fresh digest
        await sendDigestTo(peer);
      }
      return;
    }
    if (type != 'message') return;
    final raw = event['payload']?.toString() ?? '';
    if (!raw.contains('admin_act_')) return;
    Map<String, dynamic> msg;
    try {
      final d = jsonDecode(raw);
      if (d is! Map) return;
      msg = Map<String, dynamic>.from(d);
    } catch (_) {
      return;
    }
    final kind = msg['type']?.toString();
    if (!AdminActionRules.isFrameType(kind)) return;
    final from = event['sender_id']?.toString() ?? '';
    if (from.isEmpty || from == selfDeviceId()) return;
    await load();
    switch (kind) {
      case AdminActionRules.digestType:
        await _onDigest(from, msg);
      case AdminActionRules.cardsType:
        await _onCards(from, msg);
      case AdminActionRules.doneType:
        await _onDone(from, msg);
    }
  }

  /// `{type, h, items:[[id, p|d|x]]}` - p pending, d done, x cancelled/replaced.
  Map<String, dynamic> digest() {
    final items = <List<String>>[];
    final list = _entries.values.toList()
      ..sort((a, b) => b.madeAt.compareTo(a.madeAt));
    for (final e in list) {
      if (items.length >= 1500) break;
      items.add([e.id, e.pending ? 'p' : (e.state == 'done' ? 'd' : 'x')]);
    }
    return {'type': AdminActionRules.digestType, 'items': items};
  }

  Future<void> sendDigests() async {
    await load();
    final peers = await linkedPeers().catchError((_) => <String>[]);
    for (final p in peers) {
      await sendDigestTo(p);
    }
  }

  Future<void> sendDigestTo(String peer) async {
    await load();
    final now = _clock();
    final last = _digestSentAt[peer];
    if (last != null && now.difference(last) < AdminActionRules.digestGap) return;
    _digestSentAt[peer] = now;
    await _safeSend(peer, digest());
  }

  Future<void> _onDigest(String from, Map<String, dynamic> msg) async {
    final theirs = <String, String>{};
    for (final it in (msg['items'] as List? ?? const []).whereType<List>()) {
      if (it.length < 2) continue;
      theirs[it[0].toString()] = it[1].toString();
    }
    // 1) Cards they don't know (or still need) and I hold.
    final cards = <SignedBlob>[];
    // 2) Proofs for cards they still carry but I know are finished.
    final proofs = <_Entry>[];
    for (final e in _entries.values) {
      final s = theirs[e.id];
      if (e.pending && e.card != null && s == null) cards.add(e.card!.blob);
      if (!e.pending && s == 'p') proofs.add(e);
    }
    for (var i = 0; i < cards.length; i += AdminActionRules.maxPerFrame) {
      await _safeSend(from, {
        'type': AdminActionRules.cardsType,
        'cards': [
          for (final b in cards.skip(i).take(AdminActionRules.maxPerFrame)) b.toJson()
        ],
      });
    }
    if (proofs.isNotEmpty) await _sendProofs(from, proofs);
    // Receipts for cards both of us still carry (they may not have them).
    final carry = <AdminActionDone>[];
    for (final e in _entries.values) {
      // Version rule receipts go only to the server (every phone has one).
      if (e.pending && theirs[e.id] == 'p' && e.action != 'version_rule') {
        carry.addAll(e.receipts.values);
      }
    }
    carry.addAll(_loose.values);
    if (carry.isNotEmpty) {
      await _safeSend(from, {
        'type': AdminActionRules.doneType,
        'receipts': [for (final r in carry.take(100)) r.blob.toJson()],
      });
    }
    // If they have pending cards I've never seen, the cards frame they send
    // back after my digest brings them (they run the same check).
    final unknown = theirs.entries
        .where((x) => x.value == 'p' && !_entries.containsKey(x.key))
        .isNotEmpty;
    if (unknown) {
      _digestSentAt.remove(from);
      await sendDigestTo(from);
    }
  }

  Future<void> _sendProofs(String to, List<_Entry> list) async {
    final states = <Map<String, dynamic>>[];
    final cancels = <Map<String, dynamic>>[];
    final receipts = <Map<String, dynamic>>[];
    for (final e in list.take(100)) {
      final p = e.proof;
      if (p != null) {
        if (AdminActionStateNote.fromBlob(p) != null) {
          states.add(p.toJson());
        } else {
          cancels.add(p.toJson());
        }
      } else {
        for (final r in e.receipts.values) {
          receipts.add(r.blob.toJson());
        }
      }
    }
    await _safeSend(to, {
      'type': AdminActionRules.doneType,
      if (states.isNotEmpty) 'states': states,
      if (cancels.isNotEmpty) 'cancels': cancels,
      if (receipts.isNotEmpty) 'receipts': receipts,
    });
  }

  Future<void> _onCards(String from, Map<String, dynamic> msg) async {
    final list = (msg['cards'] as List? ?? const []).take(AdminActionRules.maxPerFrame);
    for (final raw in list) {
      final blob = SignedBlob.fromJson(raw);
      if (blob != null) await offerCard(blob, from: from, via: viaOf?.call(from) ?? 'mesh');
    }
  }

  Future<void> _onDone(String from, Map<String, dynamic> msg) async {
    for (final raw in (msg['states'] as List? ?? const []).take(100)) {
      final b = SignedBlob.fromJson(raw);
      if (b != null) await takeState(b, from: from);
    }
    for (final raw in (msg['cancels'] as List? ?? const []).take(100)) {
      final b = SignedBlob.fromJson(raw);
      if (b != null) await offerCard(b, from: from, via: viaOf?.call(from) ?? 'mesh');
    }
    for (final raw in (msg['receipts'] as List? ?? const []).take(200)) {
      final b = SignedBlob.fromJson(raw);
      if (b != null) await takeReceipt(b, from: from);
    }
  }

  /// Checks a card. Null = fine, else the reason.
  Future<String?> check(AdminActionCard card) async {
    final key = serverKey();
    if (key == null || key.isEmpty) return 'no_trust';
    if (card.signer == 'server') {
      return await verify(card.blob.body, card.blob.sig, key) ? null : 'bad_sig';
    }
    if (card.signer != 'admin') return 'bad_signer';
    final certBlob = card.cert;
    if (certBlob == null) return 'no_cert';
    if (!await verify(certBlob.body, certBlob.sig, key)) return 'bad_cert';
    final cert = AdminCert.fromBlob(certBlob);
    if (cert == null) return 'bad_cert';
    if (endedCerts().contains(cert.certId)) return 'cert_ended';
    var action = card.action;
    if (card.isCancel) action = _entries[card.cancels]?.action ?? 'block';
    if (!AdminActionRules.roleCan(cert.role, action)) return 'role';
    if (!await verify(card.blob.body, card.blob.sig, cert.signingKey)) return 'bad_sig';
    return null;
  }

  /// A card from a phone ([from]) or the server (`from: 'server'`).
  /// True when it was new here.
  Future<bool> offerCard(SignedBlob blob, {required String from, String via = ''}) async {
    await load();
    final card = AdminActionCard.fromBlob(blob);
    if (card == null) return false;
    final known = _entries[card.id];
    if (known != null) {
      if (!known.pending && from != 'server' && from.isNotEmpty) {
        // They still carry a finished card: tell them to stop.
        await _sendProofs(from, [known]);
      } else if (known.applied && from != 'server') {
        final mine = known.receipts[selfDeviceId()];
        if (mine != null) {
          await _safeSend(from, {
            'type': AdminActionRules.doneType,
            'receipts': [mine.blob.toJson()],
          });
        }
      }
      return false;
    }
    // The same card can arrive on two links at once: take it once.
    if (!_taking.add(card.id)) return false;
    try {
      return await _offerNew(card, from: from, via: via);
    } finally {
      _taking.remove(card.id);
    }
  }

  Future<bool> _offerNew(AdminActionCard card, {required String from, required String via}) async {
    final reason = await check(card);
    if (reason != null) {
      AppLogger.warning('ADMIN_ACT_REJECT',
          detail: 'reason=$reason id=${_tail(card.id)} from=${_tail(from)}');
      return false;
    }
    if (card.isCancel) return _takeCancel(card, from: from);
    final live = _entries.values.where((e) => e.card != null).length;
    if (live >= AdminActionRules.maxLive) {
      AppLogger.warning('ADMIN_ACT_FULL', detail: 'live=$live');
      return false;
    }
    final e = _Entry(card.id, card.action)
      ..card = card
      ..need = card.need
      ..madeAt = card.at
      ..updatedAt = _now();
    _entries[card.id] = e;
    // Receipts that came before the card.
    for (final k in _loose.keys.where((k) => k.startsWith('${card.id}|')).toList()) {
      final d = _loose.remove(k)!;
      e.receipts[d.device] = d;
      if (await _verifyReceipt(d)) e.counted.add(d.device);
      await _saveReceipt(e, d);
    }
    _recount(e, 'receipts');
    await _save(e);
    AppLogger.info('ADMIN_ACT_CARD',
        detail: 'action=${card.action} id=${_tail(card.id)} from=${from == 'server' ? 'server' : _tail(from)}');
    unawaited(_spreadCards([card.blob], except: from).catchError((_) {}));
    await _tryApply(e, via: from == 'server' ? 'server' : via);
    _publish();
    return true;
  }

  Future<bool> _takeCancel(AdminActionCard c, {required String from}) async {
    final target = _entries[c.cancels];
    if (target != null && !target.pending) {
      if (target.state == 'cancelled') return false;
      // Done before the cancel arrived: done stays.
      return false;
    }
    final e = target ?? (_Entry(c.cancels, 'block')..madeAt = c.at);
    e
      ..state = 'cancelled'
      ..card = null
      ..proof = c.blob
      ..updatedAt = _now();
    _entries[e.id] = e;
    await _save(e);
    AppLogger.info('ADMIN_ACT_CANCEL', detail: 'id=${_tail(e.id)} from=${_tail(from)}');
    unawaited(_spreadProofs([e], except: from).catchError((_) {}));
    _trimTombstones();
    _publish();
    return true;
  }

  /// A server "stop" note (done / cancelled / replaced).
  Future<bool> takeState(SignedBlob blob, {String from = ''}) async {
    await load();
    final note = AdminActionStateNote.fromBlob(blob);
    if (note == null) return false;
    final e = _entries[note.id];
    if (e == null || !e.pending) return false;
    if (!await _stopTrusted(note, e)) return false;
    e
      ..state = note.state
      ..card = null
      ..proof = blob
      ..updatedAt = _now();
    if (note.done > e.counted.length) e.extra['server_done'] = note.done;
    await _save(e);
    AppLogger.info('ADMIN_ACT_STOP', detail: 'id=${_tail(e.id)} state=${note.state}');
    unawaited(_spreadProofs([e], except: from).catchError((_) {}));
    _trimTombstones();
    _publish();
    return true;
  }

  /// A stop note is trusted when the server signed it, or an admin phone
  /// did with a valid cert whose role may do this action (done only).
  Future<bool> _stopTrusted(AdminActionStateNote note, _Entry e) async {
    final key = serverKey();
    if (key == null || key.isEmpty) return false;
    final certBlob = note.cert;
    if (certBlob == null) return verify(note.blob.body, note.blob.sig, key);
    if (note.state != 'done') return false;
    if (!await verify(certBlob.body, certBlob.sig, key)) return false;
    final cert = AdminCert.fromBlob(certBlob);
    if (cert == null || endedCerts().contains(cert.certId)) return false;
    if (!AdminActionRules.roleCan(cert.role, e.action)) return false;
    return verify(note.blob.body, note.blob.sig, cert.signingKey);
  }

  /// The admin's own phone saw enough receipts: it signs the stop so phones
  /// that can't check the receipts stop carrying the card too.
  Future<void> _signStop(_Entry e) async {
    if (!e.mine || e.state != 'done' || e.proof != null) return;
    try {
      final cert = await usableCert();
      if (cert == null) return;
      final body = AdminActionStateNote.newAdminBody(
          id: e.id, done: e.done, need: e.need, at: _clock(), cert: cert);
      e.proof = SignedBlob(body: body, sig: await sign(body));
    } catch (_) {}
  }

  Future<bool> _verifyReceipt(AdminActionDone d) async {
    if (d.device == selfDeviceId()) return true;
    final keys = await store.keysOf(d.device);
    if (keys.signingKey.isEmpty) return false;
    return verify(d.blob.body, d.blob.sig, keys.signingKey);
  }

  /// A "done" receipt (from the target phone or carried).
  Future<bool> takeReceipt(SignedBlob blob, {String from = ''}) async {
    await load();
    final d = AdminActionDone.fromBlob(blob);
    if (d == null) return false;
    final keys = await store.keysOf(d.device);
    final ok = d.device == selfDeviceId() ||
        (keys.signingKey.isNotEmpty && await verify(blob.body, blob.sig, keys.signingKey));
    if (keys.signingKey.isNotEmpty && !ok) {
      AppLogger.warning('ADMIN_ACT_FAKE_DONE', detail: 'id=${_tail(d.actionId)}');
      return false;
    }
    final e = _entries[d.actionId];
    if (e == null) {
      final k = '${d.actionId}|${d.device}';
      if (_loose.containsKey(k)) return false;
      if (_loose.length >= AdminActionRules.maxLooseReceipts) {
        _loose.remove(_loose.keys.first);
      }
      _loose[k] = d;
      await store.putReceipt(_receiptRow(d, counted: false));
      return true;
    }
    if (e.receipts.containsKey(d.device)) return false;
    e.receipts[d.device] = d;
    if (ok) e.counted.add(d.device);
    await _saveReceipt(e, d);
    final wasPending = e.pending;
    _recount(e, 'receipts');
    await _signStop(e);
    await _save(e);
    AppLogger.info('ADMIN_ACT_DONE_IN',
        detail: 'id=${_tail(d.actionId)} result=${d.result} counted=$ok '
            '${e.done}/${e.need}');
    if (wasPending && !e.pending) {
      // To everyone, also the phone that brought the receipt: it may not
      // be able to check it (no key) and needs the stop note.
      unawaited(_spreadProofs([e], except: '').catchError((_) {}));
    } else if (e.action != 'version_rule') {
      unawaited(_spreadReceipts([d], except: from).catchError((_) {}));
    }
    if (e.mine) syncSoon();
    _publish();
    return true;
  }

  void _recount(_Entry e, String why) {
    if (!e.pending) return;
    if (e.need > 0 && e.counted.length >= e.need) {
      e
        ..state = 'done'
        ..card = null
        ..updatedAt = _now();
      AppLogger.info('ADMIN_ACT_FINISHED', detail: 'id=${_tail(e.id)} by=$why');
    }
  }

  // ----------------------------------------------------------- doing it here

  Future<void> _retryApply() async {
    for (final e in _entries.values.toList()) {
      if (e.pending && !e.applied && e.card != null) await _tryApply(e, via: '');
    }
  }

  Future<void> _tryApply(_Entry e, {required String via}) async {
    final card = e.card;
    if (card == null || e.applied || !e.pending || card.isCancel) return;
    if (!_applying.add(e.id)) return;
    try {
      await _applyOnce(e, card, via: via);
    } finally {
      _applying.remove(e.id);
    }
  }

  Future<void> _applyOnce(_Entry e, AdminActionCard card, {required String via}) async {
    AdminActionPlain? plain;
    if (card.action == 'version_rule') {
      plain = AdminActionPlain(device: selfDeviceId(), user: selfUserId());
    } else {
      final pairs = await boxKeys().catchError((_) => <SimpleKeyPair>[]);
      if (pairs.isEmpty) return;
      for (final b in card.to) {
        final open = await AdminActionBoxLock.open(pairs, b.box);
        if (open == null) continue;
        try {
          plain = AdminActionPlain.fromJson(jsonDecode(utf8.decode(open)));
        } catch (_) {}
        if (plain != null) break;
      }
    }
    if (plain == null || plain.device != selfDeviceId()) return; // not for me
    var result = 'ok';
    // Never on the admin's own account.
    final cert = card.cert == null ? null : AdminCert.fromBlob(card.cert!);
    if (cert != null) {
      final certOwner = (await store.keysOf(cert.deviceId)).userId;
      if (cert.deviceId == selfDeviceId() ||
          (certOwner.isNotEmpty && certOwner == selfUserId())) {
        result = 'refused:self';
      }
    }
    var signOutAfter = false;
    if (result == 'ok') {
      try {
        result = await _doIt(card, plain);
        signOutAfter = (card.action == 'sign_out' || card.action == 'remove_phone') &&
            result == 'ok';
      } catch (error) {
        AppLogger.warning('ADMIN_ACT_DO_FAIL', detail: 'action=${card.action} $error');
        return; // try again later (next start / next card copy)
      }
    }
    final body = AdminActionDone.newBody(
      actionId: card.id,
      device: selfDeviceId(),
      user: selfUserId(),
      result: result,
      at: _clock(),
      build: build,
      via: via,
    );
    final d = AdminActionDone.fromBlob(SignedBlob(body: body, sig: await sign(body)))!;
    e.applied = true;
    e.receipts[d.device] = d;
    e.counted.add(d.device);
    await _saveReceipt(e, d);
    _recount(e, 'receipts');
    await _save(e);
    AppLogger.info('ADMIN_ACT_APPLIED',
        detail: 'action=${card.action} id=${_tail(card.id)} result=$result via=$via');
    if (card.action != 'version_rule') {
      await _spreadReceipts([d], except: '').catchError((_) {});
    }
    unawaited(syncWithServer().catchError((_) {}));
    if (signOutAfter) {
      // Give the receipt time to leave the phone first.
      unawaited(Future<void>.delayed(const Duration(seconds: 2), () async {
        await doers.signOut(removed: card.action == 'remove_phone');
        await AdminActionSignOut.onSignedOut?.call();
      }).catchError((_) {}));
    }
    _publish();
  }

  Future<String> _doIt(AdminActionCard card, AdminActionPlain plain) async {
    switch (card.action) {
      case 'block':
      case 'unblock':
        final inner = card.inner;
        if (inner == null) return 'refused:no_inner';
        return await doers.block(inner) ? 'ok' : 'already';
      case 'off':
      case 'active':
        final inner = card.inner;
        if (inner != null) await doers.block(inner);
        final closed = card.action == 'off';
        final was = (await store.readSetting(AdminActionDoers.closedKey) ?? '') == '1';
        await doers.setClosed(closed);
        AdminClosedFlag.closed.value = closed;
        return was == closed ? 'already' : 'ok';
      case 'wifi_rule':
        final policy = plain.detail['policy'];
        await doers.wifi(policy is Map
            ? Map<String, dynamic>.from(policy)
            : {'wifi_radio_policy': plain.detail['wifi_radio_policy']});
        return 'ok';
      case 'admin_badge':
        final inner = card.inner;
        if (inner == null) return 'refused:no_inner';
        return await doers.badge(inner) ? 'ok' : 'already';
      case 'version_rule':
        final inner = card.inner;
        if (inner == null) return 'refused:no_inner';
        return await doers.versionRule(inner) ? 'ok' : 'already';
      case 'sign_out':
      case 'remove_phone':
        return 'ok'; // done after the receipt leaves (see _tryApply)
      default:
        // Bundle 221: get_chat / get_file / delete_completely.
        final chat = doers.chat221;
        return chat == null ? 'refused:unknown' : await chat(card, plain);
    }
  }

  // ------------------------------------------------------- making (offline)

  static String _newId() {
    final r = Random.secure();
    return 'aa_${List<int>.generate(12, (_) => r.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }

  /// An admin on this phone makes a card (used when there is no server).
  /// Throws a short message when it can't.
  Future<String> make({
    required String action,
    required String targetUserId,
    required String label,
    List<String> targetDevices = const [],
    Map<String, dynamic> detail = const {},
    String words = '',
    SignedBlob? inner,
    // Bundle 221 (chat requests): answers locked for this key, 1 answer
    // needed (get_chat / get_file), the request it belongs to.
    String replyKey = '',
    int? need,
    String parent = '',
  }) async {
    await load();
    final signIn = await adminSignIn?.call();
    if (signIn == null) throw StateError('Admin is not on for this phone.');
    if (!AdminActionRules.roleCan(signIn.role, action)) {
      throw StateError("Your admin role can't do this.");
    }
    final me = {selfUserId(), selfDeviceId()}..remove('');
    if (me.contains(targetUserId) || targetDevices.any(me.contains)) {
      throw StateError("You can't do this on your own account.");
    }
    final cert = await usableCert();
    if (cert == null) {
      throw StateError('Connect to the server once to turn on offline admin actions.');
    }
    if (pendingMine >= AdminActionRules.maxPendingPerAdmin) {
      throw StateError('Finish or cancel some actions first');
    }
    var innerBlob = inner;
    if (innerBlob == null &&
        const {'block', 'unblock', 'off', 'active'}.contains(action) &&
        makeBlockInner != null) {
      innerBlob = await makeBlockInner!(
        userId: targetUserId,
        devices: targetDevices,
        name: label,
        block: action == 'block' || action == 'off',
      );
    }
    final devices = <String>{
      ...targetDevices,
      if (AdminActionRules.perPerson.contains(action) || targetDevices.isEmpty)
        ...await store.phonesOf(targetUserId),
    }..removeWhere((d) => d.isEmpty || me.contains(d));
    final boxes = <AdminActionBox>[];
    final reached = <String>[];
    if (action != 'version_rule') {
      for (final d in devices.toList()..sort()) {
        final keys = await store.keysOf(d);
        if (keys.identityKey.isEmpty) continue;
        final plain = AdminActionPlain(device: d, user: targetUserId, detail: detail);
        try {
          boxes.add(AdminActionBox(_newId().substring(3, 11),
              await AdminActionBoxLock.lock(keys.identityKey, utf8.encode(jsonEncode(plain.toJson())))));
          reached.add(d);
        } catch (_) {}
      }
      if (boxes.isEmpty) {
        throw StateError("This phone doesn't know $label's phone yet. Connect to the server.");
      }
    }
    final id = _newId();
    final body = AdminActionCard.newBody(
      id: id,
      action: action,
      at: _clock(),
      by: signIn.username,
      cert: cert,
      need: action == 'version_rule' ? 0 : (need ?? boxes.length).clamp(1, boxes.length),
      to: boxes,
      inner: innerBlob,
      parent: parent,
      replyKey: replyKey,
    );
    final blob = SignedBlob(body: body, sig: await sign(body));
    final card = AdminActionCard.fromBlob(blob);
    if (card == null) throw StateError('This action is too big to send.');
    final e = _Entry(id, action)
      ..card = card
      ..need = card.need
      ..mine = true
      ..label = label
      ..madeAt = card.at
      ..updatedAt = _now()
      ..extra = {
        'user': targetUserId,
        'devices': reached,
        if (words.isNotEmpty) 'words': words,
        if (detail.isNotEmpty) 'detail': detail,
      };
    _entries[id] = e;
    await _save(e);
    AppLogger.info('ADMIN_ACT_MADE',
        detail: 'action=$action id=${_tail(id)} phones=${boxes.length}');
    unawaited(_spreadCards([blob], except: '').catchError((_) {}));
    unawaited(syncWithServer().catchError((_) {}));
    _publish();
    return id;
  }

  /// Cancel: on the server when online (server-made or synced cards), else a
  /// signed cancel card that travels like the action.
  Future<void> cancel(String id) async {
    await load();
    final signIn = await adminSignIn?.call();
    if (signIn == null) throw StateError('Admin is not on for this phone.');
    final e = _entries[id];
    if (e != null && e.action == 'version_rule') {
      throw StateError('Change the rule on the App version page.');
    }
    if (e != null && !e.pending) throw StateError('This action is not pending.');
    if (server != null && (serverOnline?.call() ?? false)) {
      try {
        await server!.cancel(signIn.token, id);
        unawaited(syncWithServer().catchError((_) {}));
        return;
      } on AdminActionRefused catch (r) {
        if (r.code == 'use_app_version_page') {
          throw StateError('Change the rule on the App version page.');
        }
        if (r.status != 404) throw StateError(r.message);
      } catch (_) {
        // fall through to the offline cancel card
      }
    }
    if (e == null) throw StateError('This action is not on this phone.');
    final cert = await usableCert();
    if (cert == null) {
      throw StateError('Connect to the server once to turn on offline admin actions.');
    }
    if (!AdminActionRules.roleCan(signIn.role, e.action)) {
      throw StateError("Your admin role can't do this.");
    }
    final body = AdminActionCard.newBody(
      id: _newId(),
      action: 'cancel',
      at: _clock(),
      by: signIn.username,
      cert: cert,
      need: 0,
      to: const [],
      cancels: id,
    );
    final blob = SignedBlob(body: body, sig: await sign(body));
    final card = AdminActionCard.fromBlob(blob)!;
    e.extra['cancel_card'] = blob.toJson();
    await _takeCancel(card, from: '');
    unawaited(syncWithServer().catchError((_) {}));
  }

  // ------------------------------------------------------------ the server

  Future<void> syncWithServer() async {
    final s = server;
    if (s == null || _syncBusy) return;
    _syncBusy = true;
    try {
      await load();
      final key = await signingKey();
      for (var page = 0; page < 5; page++) {
        final cards = <SignedBlob>[];
        final receipts = <SignedBlob>[];
        final labels = <Map<String, dynamic>>[];
        for (final e in _entries.values) {
          if (e.pending && e.card != null) cards.add(e.card!.blob);
          if (e.state == 'cancelled' && e.extra['cancel_card'] is Map &&
              e.extra['cancel_sent'] != true) {
            final c = SignedBlob.fromJson(e.extra['cancel_card']);
            if (c != null) cards.add(c);
          }
          if (e.pending && e.action != 'version_rule') {
            receipts.addAll(e.receipts.values.map((r) => r.blob));
          }
          final own = e.receipts[selfDeviceId()];
          if (own != null && e.extra['own_sent'] != true &&
              !(e.pending && e.action != 'version_rule')) {
            receipts.add(own.blob);
          }
          if (e.mine && e.extra['label_sent'] != true && e.label.isNotEmpty) {
            labels.add({
              'id': e.id,
              'user_id': e.extra['user'] ?? '',
              'label': e.label,
              'devices': e.extra['devices'] ?? const [],
              if (e.extra['detail'] is Map) 'detail': e.extra['detail'],
              if ((e.extra['words'] ?? '').toString().isNotEmpty) 'words': e.extra['words'],
            });
          }
        }
        receipts.addAll(_loose.values.map((d) => d.blob));
        AdminActionSyncOut out;
        try {
          out = await s.sync(
            cards: cards.take(200).toList(),
            receipts: receipts.take(500).toList(),
            have: [
              for (final e in _entries.values) if (e.pending) e.id,
              for (final e in _entries.values) if (!e.pending) e.id,
            ].take(2000).toList(),
            signingKey: key,
            labels: labels.take(100).toList(),
            build: build,
          );
        } on AdminActionUnauthorized {
          await _syncMine(s, key);
          return;
        }
        for (final e in _entries.values) {
          if (labels.any((l) => l['id'] == e.id)) e.extra['label_sent'] = true;
          if (e.extra['cancel_card'] is Map) e.extra['cancel_sent'] = true;
          if (e.receipts.containsKey(selfDeviceId())) e.extra['own_sent'] = true;
        }
        for (final id in out.tooMany) {
          final e = _entries[id];
          if (e != null) e.extra['too_many'] = true;
        }
        for (final b in out.cards) {
          await offerCard(b, from: 'server', via: 'server');
        }
        for (final b in out.states) {
          await takeState(b, from: 'server');
        }
        for (final e in _entries.values.where((e) => e.mine || e.applied)) {
          await _save(e);
        }
        if (!out.more) break;
      }
      _publish();
    } catch (error) {
      AppLogger.info('ADMIN_ACT_SYNC_SKIP', detail: '$error');
    } finally {
      _syncBusy = false;
    }
  }

  Future<void> _syncMine(AdminActionServer s, String key) async {
    final mine = <SignedBlob>[
      for (final e in _entries.values)
        if (e.receipts[selfDeviceId()] case final AdminActionDone d) d.blob,
    ];
    final out = await s.mine(receipts: mine.take(200).toList(), signingKey: key, build: build);
    for (final b in out.cards) {
      await offerCard(b, from: 'server', via: 'server');
    }
    for (final b in out.states) {
      await takeState(b, from: 'server');
    }
  }

  /// The admin list from the server (online), merged by the screen.
  Future<List<Map<String, dynamic>>> serverList() async {
    final s = server;
    final signIn = await adminSignIn?.call();
    if (s == null || signIn == null) return const [];
    return s.list(signIn.token);
  }

  // -------------------------------------------------------------- spreading

  Future<void> _spreadCards(List<SignedBlob> cards, {required String except}) async {
    final peers = await linkedPeers().catchError((_) => <String>[]);
    for (final p in peers) {
      if (p == except) continue;
      await _safeSend(p, {
        'type': AdminActionRules.cardsType,
        'cards': [for (final b in cards.take(AdminActionRules.maxPerFrame)) b.toJson()],
      });
    }
  }

  Future<void> _spreadReceipts(List<AdminActionDone> list, {required String except}) async {
    final peers = await linkedPeers().catchError((_) => <String>[]);
    for (final p in peers) {
      if (p == except) continue;
      await _safeSend(p, {
        'type': AdminActionRules.doneType,
        'receipts': [for (final d in list) d.blob.toJson()],
      });
    }
  }

  Future<void> _spreadProofs(List<_Entry> list, {required String except}) async {
    final peers = await linkedPeers().catchError((_) => <String>[]);
    for (final p in peers) {
      if (p == except) continue;
      await _sendProofs(p, list);
    }
  }

  Future<void> _safeSend(String peer, Map<String, dynamic> payload) async {
    try {
      await send(peer, payload);
    } catch (_) {}
  }

  // ------------------------------------------------------------- keeping

  void _trimTombstones() {
    final stopped = _entries.values.where((e) => !e.pending).toList();
    if (stopped.length <= AdminActionRules.maxTombstones) return;
    stopped.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    final drop = stopped
        .take(stopped.length - AdminActionRules.maxTombstones)
        .where((e) => !e.mine)
        .map((e) => e.id)
        .toList();
    for (final id in drop) {
      _entries.remove(id);
    }
    unawaited(store.deleteActions(drop).catchError((_) {}));
  }

  Future<void> _save(_Entry e) async {
    try {
      await store.putAction({
        'id': e.id,
        'action': e.action,
        'body': e.card?.blob.body ?? '',
        'sig': e.card?.blob.sig ?? '',
        'state': e.state,
        'need': e.need,
        'done': e.done,
        'mine': e.mine ? 1 : 0,
        'applied': e.applied ? 1 : 0,
        'label': e.label,
        'made_at': e.madeAt,
        'updated_at': e.updatedAt,
        'proof': e.proof == null ? '' : jsonEncode(e.proof!.toJson()),
        'extra': e.extra.isEmpty ? '' : jsonEncode(e.extra),
      });
    } catch (error) {
      AppLogger.warning('ADMIN_ACT_SAVE_FAIL', detail: '$error');
    }
  }

  Future<void> _saveReceipt(_Entry e, AdminActionDone d) async {
    try {
      await store.putReceipt(_receiptRow(d, counted: e.counted.contains(d.device)));
    } catch (_) {}
  }

  Map<String, Object?> _receiptRow(AdminActionDone d, {required bool counted}) => {
        'action_id': d.actionId,
        'device_id': d.device,
        'body': d.blob.body,
        'sig': d.blob.sig,
        'counted': counted ? 1 : 0,
        'at': d.at,
      };

  String _now() => _clock().toUtc().toIso8601String();

  static int _int(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;

  static SignedBlob? _blobOf(Object? raw) {
    final s = raw?.toString() ?? '';
    if (s.isEmpty) return null;
    try {
      return SignedBlob.fromJson(jsonDecode(s));
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _mapOf(Object? raw) {
    final s = raw?.toString() ?? '';
    if (s.isEmpty) return <String, dynamic>{};
    try {
      final d = jsonDecode(s);
      return d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static String _tail(String v) => v.length <= 6 ? v : v.substring(v.length - 6);

  @visibleForTesting
  String? stateOf(String id) => _entries[id]?.state;
  @visibleForTesting
  bool hasCard(String id) => _entries[id]?.card != null;
  @visibleForTesting
  int doneOf(String id) => _entries[id]?.done ?? 0;
  @visibleForTesting
  bool appliedOf(String id) => _entries[id]?.applied ?? false;
}
