import 'package:firebase_auth/firebase_auth.dart';

/// A [User] that answers `uid` and nothing else — enough for providers whose
/// only question is "which account is this" (e.g. auth-gated room providers).
/// Any other member access throws via [noSuchMethod], which is the desired
/// behaviour in a test: it names the unexpected dependency instead of
/// silently faking it.
User fakeUser(String uid) => _FakeUser(uid);

class _FakeUser implements User {
  @override
  final String uid;
  _FakeUser(this.uid);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
