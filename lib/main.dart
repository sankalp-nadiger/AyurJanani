import 'package:flutter/material.dart';
import 'package:prenova/core/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:prenova/features/auth/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    String url = 'https://ydrawxmojixpdygicmlj.supabase.co';
    String anonKey =
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlkcmF3eG1vaml4cGR5Z2ljbWxqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDk4MjIzODIsImV4cCI6MjA2NTM5ODM4Mn0._8xwALJl_vbR7tAeTxPLsQIUwYBReAqV3yqS1zWTsCk';

    debugPrint("Initializing Supabase with URL: $url");

    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
      debug: true,
    );

    // Check if we have a session
    final session = Supabase.instance.client.auth.currentSession;
    debugPrint("Initial session state: ${session?.user.id ?? 'No session'}");

    // Print JWT token at startup
    debugPrint("Initial JWT token: ${session?.accessToken ?? 'No JWT token'}");
  } catch (e) {
    debugPrint("Error initializing Supabase: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkThemeMode,
      home: const AuthGate(),
    );
  }
}
