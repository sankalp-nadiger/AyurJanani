import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final SupabaseClient supabase = Supabase.instance.client;

  // Get current session
  Session? get currentSession => supabase.auth.currentSession;

  // Get current user
  User? get currentUser => supabase.auth.currentUser;

  // Get JWT token from current session
  String? get jwtToken => supabase.auth.currentSession?.accessToken;

  // Sign in with email and password
  Future<void> signInWithEmailPassword(String email, String password) async {
    try {
      debugPrint('Attempting to sign in with email: $email');
      debugPrint('Password length: ${password.length}');

      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      debugPrint('Sign in response received');
      debugPrint('Session exists: ${response.session != null}');
      debugPrint('User exists: ${response.user != null}');
      debugPrint('User ID: ${response.user?.id ?? 'No user ID'}');
      debugPrint('User email: ${response.user?.email ?? 'No email'}');
      debugPrint(
          'Session user ID: ${response.session?.user.id ?? 'No session user ID'}');

      if (response.session == null) {
        debugPrint('Sign in failed: No session returned');
        throw Exception('Invalid email or password');
      }

      debugPrint('Sign in successful: ${response.session!.user.email}');

      // Verify the session is properly set
      final currentSession = supabase.auth.currentSession;
      debugPrint(
          'Current session after login: ${currentSession?.user.id ?? 'No current session'}');
    } catch (e) {
      debugPrint('Sign in error details: $e');
      debugPrint('Error type: ${e.runtimeType}');

      if (e is AuthException) {
        debugPrint('AuthException details:');
        debugPrint('  Message: ${e.message}');
        debugPrint('  Status code: ${e.statusCode}');

        // Handle specific auth errors
        if (e.message.contains('Email not confirmed')) {
          throw Exception(
              'Please check your email and confirm your account before signing in');
        } else if (e.message.contains('Invalid login credentials')) {
          throw Exception(
              'Invalid email or password. Please check your credentials.');
        } else if (e.message.contains('Too many requests')) {
          throw Exception('Too many login attempts. Please try again later.');
        }

        throw Exception('Login failed: ${e.message}');
      }
      throw Exception('Login failed: $e');
    }
  }

  // Sign up with email and password
  Future<void> signUpWithEmailPassword(String email, String password) async {
    try {
      debugPrint('Attempting to sign up with email: $email');

      final response = await supabase.auth.signUp(
        email: email,
        password: password,
      );

      debugPrint('Sign up response: ${response.user?.id ?? 'No user'}');
      debugPrint(
          'Sign up session: ${response.session?.user.id ?? 'No session'}');

      if (response.user == null) {
        debugPrint('Sign up failed: No user returned');
        throw Exception('Sign-up failed');
      }

      debugPrint('Sign up successful: ${response.user!.email}');
    } catch (e) {
      debugPrint('Sign up error details: $e');
      if (e is AuthException) {
        // Handle specific Supabase auth errors
        final errorCode = e.statusCode.toString();
        switch (errorCode) {
          case '400':
            if (e.message.contains('email_address_invalid')) {
              throw Exception('Invalid email address format');
            } else if (e.message.contains('already_registered')) {
              throw Exception('User with this email already exists');
            } else if (e.message.contains('weak_password')) {
              throw Exception(
                  'Password is too weak. Use at least 6 characters');
            }
            break;
          default:
            throw Exception('Sign-up error: ${e.message}');
        }
      }
      throw Exception('Sign-up error: $e');
    }
  }

  // Update password
  Future<void> updatePassword(String newPassword) async {
    try {
      await supabase.auth.updateUser(UserAttributes(password: newPassword));
    } catch (e) {
      throw Exception("Password update failed: $e");
    }
  }

  // Reset Password
  Future<void> resetPassword(String email) async {
    try {
      await supabase.auth
          .resetPasswordForEmail(email, redirectTo: "unihub://auth/callback");
    } catch (e) {
      throw Exception('Password reset failed: $e');
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await supabase.auth.signOut();
      // No need to clear tokens from secure storage
      debugPrint('Signed out from Supabase');
    } catch (e) {
      throw Exception('Sign-out error: $e');
    }
  }

  String? getCurrentUserEmail() {
    final session = supabase.auth.currentSession;
    return session?.user.email;
  }

  // Listen to auth state changes
  Stream<AuthState> get authStateChanges => supabase.auth.onAuthStateChange;

  // Sign in with Google
  Future<void> signInWithGoogle() async {
    try {
      // Trigger Google OAuth flow
      await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'https://ydrawxmojixpdygicmlj.supabase.co/auth/v1/callback',
      );
    } catch (e) {
      throw Exception('Google Sign-in error: $e');
    }
  }

  String? getCurrentUsername() {
    final user = supabase.auth.currentUser;
    if (user == null) return null;

    // Try to get the username from user metadata
    final metadata = user.userMetadata;
    if (metadata != null) {
      // First try name from metadata
      if (metadata['name'] != null) {
        return metadata['name'] as String;
      }
      // Then try preferred_username
      if (metadata['preferred_username'] != null) {
        return metadata['preferred_username'] as String;
      }
      // Finally try full_name
      if (metadata['full_name'] != null) {
        return metadata['full_name'] as String;
      }
    }

    // Fall back to email if no username is found
    return user.email?.split('@').first;
  }

  // Check if email confirmation is required
  Future<bool> isEmailConfirmationRequired() async {
    try {
      final session = supabase.auth.currentSession;
      return session == null;
    } catch (e) {
      debugPrint('Error checking email confirmation: $e');
      return false;
    }
  }

  // Resend email confirmation
  Future<void> resendEmailConfirmation(String email) async {
    try {
      await supabase.auth.resend(
        type: OtpType.signup,
        email: email,
      );
      debugPrint('Email confirmation resent to: $email');
    } catch (e) {
      debugPrint('Error resending email confirmation: $e');
      throw Exception('Failed to resend email confirmation: $e');
    }
  }
}

// Get current username
