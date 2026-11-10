import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyfta/core/auth/auth_controller.dart';
import 'package:lyfta/core/auth/auth_state.dart';
import 'package:lyfta/features/chat/data/participant_directory.dart';
import 'package:lyfta/features/chat/domain/conversation.dart';
import 'package:lyfta/features/chat/presentation/conversations_controller.dart';

class _FakeAuth extends AuthController {
  @override
  AuthState build() => AuthState.authenticated(
        roles: {UserRole.coach},
        tenantId: 't',
        userId: 'coach-1',
      );
}

class _FakeConversations extends ConversationsController {
  _FakeConversations(this.items);

  List<Conversation> items;

  @override
  Future<List<Conversation>> build() async => items;
}

class _FakeDirectory extends ParticipantDirectoryRepository {
  _FakeDirectory() : super(Dio());

  final calls = <List<String>>[];

  @override
  Future<Map<String, String>> names(Iterable<String> ids) async {
    calls.add(ids.toList());
    return {for (final id in ids) id: 'Nome $id'};
  }
}

Conversation _conv(String id, String student) => Conversation(
      id: id,
      studentId: student,
      coachId: 'coach-1',
      createdAt: DateTime(2026),
    );

void main() {
  test('pede só os ids dos outros participantes e não refaz sem mudança',
      () async {
    final fake = _FakeDirectory();
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(_FakeAuth.new),
      conversationsProvider.overrideWith(
        () => _FakeConversations([_conv('c1', 's-2'), _conv('c2', 's-1')]),
      ),
      participantDirectoryRepositoryProvider.overrideWithValue(fake),
    ],);
    addTearDown(container.dispose);

    await container.read(conversationsProvider.future);
    final directory = await container.read(participantDirectoryProvider.future);
    expect(directory, {'s-1': 'Nome s-1', 's-2': 'Nome s-2'});
    expect(fake.calls, [
      ['s-1', 's-2'],
    ]);

    // Conversas recarregadas com os mesmos participantes: sem nova consulta.
    await container.read(conversationsProvider.notifier).refresh();
    await container.read(participantDirectoryProvider.future);
    expect(fake.calls, hasLength(1));
  });

  test('sem conversas não consulta o servidor', () async {
    final fake = _FakeDirectory();
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(_FakeAuth.new),
      conversationsProvider.overrideWith(() => _FakeConversations(const [])),
      participantDirectoryRepositoryProvider.overrideWithValue(fake),
    ],);
    addTearDown(container.dispose);

    await container.read(conversationsProvider.future);
    expect(await container.read(participantDirectoryProvider.future), isEmpty);
    expect(fake.calls, isEmpty);
  });

  test('mais de 100 participantes viram vários lotes', () async {
    final dio = Dio()..httpClientAdapter = _CountingAdapter();
    final names = await ParticipantDirectoryRepository(dio)
        .names([for (var i = 0; i < 250; i++) 'id-$i']);
    expect(names, hasLength(250));
    expect((dio.httpClientAdapter as _CountingAdapter).sizes, [100, 100, 50]);
  });
}

class _CountingAdapter implements HttpClientAdapter {
  final sizes = <int>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final ids = (options.queryParameters['ids'] as String).split(',');
    sizes.add(ids.length);
    final items = ids.map((id) => '{"id":"$id","name":"N $id"}').join(',');
    return ResponseBody.fromString(
      '{"items":[$items]}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
