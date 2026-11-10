import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pustlivebus/screens/admin_screen.dart';
import 'package:pustlivebus/services/transit_repository.dart';

import 'transit_repository_test.dart' show MemoryStore;

class _RestoredUser extends Fake implements User {}

class _RestoredAuth extends Fake implements FirebaseAuth {
  int userReads = 0;
  int attempts = 0;

  @override
  User get currentUser {
    userReads++;
    return _RestoredUser();
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    attempts++;
    throw FirebaseAuthException(code: 'invalid-credential');
  }
}

void main() {
  testWidgets('Restored session cannot open admin or bypass failed sign-in', (
    tester,
  ) async {
    final repository = TransitRepository(store: MemoryStore())
      ..firebaseReady = true;
    final auth = _RestoredAuth();
    await tester.pumpWidget(
      MaterialApp(
        home: AdminScreen(repository: repository, auth: auth),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Administrator sign-in'), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);
    expect(find.byType(TabBar), findsNothing);
    expect(auth.userReads, 0);

    await tester.enterText(find.byType(TextField).first, 'admin@example.com');
    await tester.enterText(find.byType(TextField).last, 'incorrect-password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(auth.attempts, 1);
    expect(auth.userReads, 0);
    expect(find.textContaining('[invalid-credential]'), findsOneWidget);
    expect(find.byType(TabBar), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    repository.dispose();
  });
}
