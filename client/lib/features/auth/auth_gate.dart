import 'package:flutter/material.dart';
import 'package:prenova/features/auth/presentation/welcome_pg.dart';
import 'package:prenova/features/auth/presentation/onboarding.dart';
import 'package:prenova/features/dashboard/presentation/dashboard.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // Handle connection state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Handle errors
        if (snapshot.hasError) {
          debugPrint('AuthGate Error: ${snapshot.error}');
          return Scaffold(
            body: Center(
              child: Text('Error: ${snapshot.error}'),
            ),
          );
        }

        // Get current session
        final session = Supabase.instance.client.auth.currentSession;
        debugPrint('Current Session: ${session?.user.id}');

        // Check if we have a valid session
        if (session == null) {
          debugPrint('No session found, showing WelcomePage');
          return const WelcomePage();
        }

        // We have a valid session, check if user has completed onboarding
        debugPrint('Valid session found, checking onboarding status');
        return FutureBuilder(
          future: _checkOnboardingStatus(session.user.id),
          builder: (context, onboardingSnapshot) {
            if (onboardingSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            if (onboardingSnapshot.hasError) {
              debugPrint('Onboarding check error: ${onboardingSnapshot.error}');
              // If there's an error checking onboarding, show dashboard
              return DashboardScreen();
            }

            final hasCompletedOnboarding = onboardingSnapshot.data ?? false;

            if (hasCompletedOnboarding) {
              debugPrint('User has completed onboarding, showing Dashboard');
              return DashboardScreen();
            } else {
              debugPrint(
                  'User needs to complete onboarding, showing OnboardingPage');
              return const OnboardingPage();
            }
          },
        );
      },
    );
  }

  Future<bool> _checkOnboardingStatus(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('user_name')
          .eq('UID', userId)
          .maybeSingle();

      return response != null && response['user_name'] != null;
    } catch (e) {
      debugPrint('Error checking onboarding status: $e');
      return false;
    }
  }
}
