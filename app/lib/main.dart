import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:familyapp/screens/auth_screen.dart';
import 'package:familyapp/screens/family_screen.dart';
import 'package:familyapp/screens/home_screen.dart';
import 'package:familyapp/state/auth_store.dart';

void main() {
  runApp(const ProviderScope(child: FamilyApp()));
}

class FamilyApp extends StatelessWidget {
  const FamilyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FamilyApp',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6B4F)),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

/// Shows the login flow until a family member is signed in.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(authStoreProvider.select((state) => state.status));
    return switch (status) {
      AuthStatus.checking => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      AuthStatus.familyRequired => const FamilyScreen(),
      AuthStatus.signedOut => const AuthScreen(),
      AuthStatus.signedIn => const HomeScreen(),
    };
  }
}
