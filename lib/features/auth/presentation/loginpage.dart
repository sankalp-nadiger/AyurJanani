import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:prenova/core/theme/app_pallete.dart';
import 'package:prenova/core/theme/starry_bg.dart';
import 'package:prenova/features/auth/auth_service.dart';
import 'package:prenova/features/auth/presentation/glowing_btn.dart';
import 'package:prenova/features/auth/presentation/registerpage.dart';
import 'package:prenova/features/auth/presentation/onboarding.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> with TickerProviderStateMixin {
  final authservice = AuthService();
  final _emailcontroller = TextEditingController();
  final _passwordcontroller = TextEditingController();
  final FlutterSecureStorage secureStorage = const FlutterSecureStorage();
  bool _obscurePassword = true;
  bool _isLoading = false;

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: Duration(milliseconds: 1000),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));

    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _emailcontroller.dispose();
    _passwordcontroller.dispose();
    super.dispose();
  }

  void login() async {
    final email = _emailcontroller.text.trim();
    final password = _passwordcontroller.text.trim();

    debugPrint('Login attempt with email: $email');

    if (email.isEmpty || password.isEmpty) {
      _showErrorSnackBar("Please enter both email and password.");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      debugPrint('Calling authservice.signInWithEmailPassword...');
      await authservice.signInWithEmailPassword(email, password);

      // Check if we have a valid session
      final session = Supabase.instance.client.auth.currentSession;
      debugPrint('Session after login: ${session?.user.id ?? 'No session'}');

      // Node.js backend login
      try {
        print('=== NODE.JS BACKEND LOGIN ATTEMPT ===');
        debugPrint('=== NODE.JS BACKEND LOGIN ATTEMPT ===');
        print('Email: $email');
        debugPrint('Email: $email');

        final nodeResponse = await http.post(
          Uri.parse('https://fitfull.onrender.com/api/users/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        );
        print('Node.js backend status code: ${nodeResponse.statusCode}');
        debugPrint('Node.js backend status code: ${nodeResponse.statusCode}');
        print('Node.js backend response body: ' + nodeResponse.body);
        debugPrint('Node.js backend response body: ' + nodeResponse.body);
        if (nodeResponse.statusCode == 200 || nodeResponse.statusCode == 201) {
          final responseBody = jsonDecode(nodeResponse.body);
          print('Parsed response body: ${jsonEncode(responseBody)}');
          debugPrint('Parsed response body: ${jsonEncode(responseBody)}');
          print(
              'accessToken exists: ${responseBody != null && responseBody['data'] != null && responseBody['data']['accessToken'] != null}');
          debugPrint(
              'accessToken exists: ${responseBody != null && responseBody['data'] != null && responseBody['data']['accessToken'] != null}');
          if (responseBody != null &&
              responseBody['data'] != null &&
              responseBody['data']['accessToken'] != null) {
            final nodejsToken = responseBody['data']['accessToken'];
            await secureStorage.write(key: 'nodejs_token', value: nodejsToken);
            debugPrint('Nodejs token stored in secure storage: ' + nodejsToken);
            print('Nodejs token stored in secure storage: ' +
                nodejsToken); // Print to terminal
            debugPrint('Nodejs token: ' + nodejsToken);
            print('Nodejs token: ' + nodejsToken); // Print to terminal
            // Read back and print from secure storage
            final storedToken = await secureStorage.read(key: 'nodejs_token');
            debugPrint(
                'Nodejs token from secure storage: ' + (storedToken ?? 'null'));
            print('Nodejs token from secure storage: ' +
                (storedToken ?? 'null')); // Print to terminal
          } else {
            print('No nodejs token found in Node.js backend response');
            debugPrint('No nodejs token found in Node.js backend response');
            print(
                'Response body keys: ${responseBody != null ? responseBody.keys.toList() : 'null'}');
            debugPrint(
                'Response body keys: ${responseBody != null ? responseBody.keys.toList() : 'null'}');
          }
        } else {
          print(
              'Node.js backend login failed: ${nodeResponse.statusCode} ${nodeResponse.body}');
          debugPrint(
              'Node.js backend login failed: ${nodeResponse.statusCode} ${nodeResponse.body}');
        }
      } catch (e) {
        debugPrint('Error logging in to Node.js backend: $e');
      }

      if (session != null) {
        debugPrint('Login successful, navigating...');
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else {
        debugPrint('Login successful but no session created');
        throw Exception('Login successful but no session created');
      }
    } catch (e) {
      debugPrint('Login error caught: $e');
      if (mounted) {
        String errorMessage = "Login failed. Please try again.";
        if (e is AuthException) {
          errorMessage = e.message;
        } else if (e.toString().contains('Invalid email or password')) {
          errorMessage =
              "Invalid email or password. Please check your credentials.";
        } else if (e.toString().contains('network')) {
          errorMessage =
              "Network error. Please check your internet connection.";
        }
        _showErrorSnackBar(errorMessage);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await authservice.signInWithGoogle();

      // Check if we have a valid session
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        if (mounted) {
          // Let AuthGate handle the navigation automatically
          // Just pop back to the root, AuthGate will show the appropriate screen
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else {
        throw Exception('Google sign-in successful but no session created');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(e is AuthException
            ? e.message
            : "Google Sign-in failed. Please try again.");
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppPallete.errorColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.all(16),
      ),
    );
  }

  // Test function to create a test account
  void _createTestAccount() async {
    try {
      debugPrint('Creating test account...');
      await authservice.signUpWithEmailPassword(
          'testuser123@gmail.com', 'password123');
      debugPrint('Test account created successfully');
      _showErrorSnackBar(
          'Test account created! You can now sign in with testuser123@gmail.com / password123');
    } catch (e) {
      debugPrint('Error creating test account: $e');
      String errorMessage = 'Error creating test account: $e';

      // Handle specific Supabase errors
      if (e.toString().contains('email_address_invalid')) {
        errorMessage =
            'Email validation failed. Try using a different email format.';
      } else if (e.toString().contains('already_registered')) {
        errorMessage =
            'Test account already exists! Try signing in with testuser123@gmail.com / password123';
      } else if (e.toString().contains('weak_password')) {
        errorMessage = 'Password is too weak. Please use a stronger password.';
      }

      _showErrorSnackBar(errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StarryBackground(
      child: Scaffold(
        backgroundColor: AppPallete.transparentColor,
        body: SafeArea(
          child: SingleChildScrollView(
            physics: BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    children: [
                      SizedBox(height: 60),

                      // Logo with enhanced styling
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: Image.asset(
                            'assets/logo.jpg',
                            height: 280,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),

                      SizedBox(height: 40),

                      // Welcome text
                      Text(
                        "Welcome Back",
                        style: GoogleFonts.poppins(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: AppPallete.textColor,
                          letterSpacing: 1.2,
                        ),
                      ),

                      SizedBox(height: 8),

                      Text(
                        "Sign in to continue your journey",
                        style: GoogleFonts.lato(
                          fontSize: 16,
                          color: AppPallete.textColor.withOpacity(0.7),
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      SizedBox(height: 40),

                      // Email field
                      _buildStyledTextField(
                        controller: _emailcontroller,
                        label: "Email Address",
                        hint: "Enter your email",
                        icon: LucideIcons.mail,
                        keyboardType: TextInputType.emailAddress,
                      ),

                      SizedBox(height: 20),

                      // Password field
                      _buildStyledTextField(
                        controller: _passwordcontroller,
                        label: "Password",
                        hint: "Enter your password",
                        icon: LucideIcons.lock,
                        obscureText: _obscurePassword,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? LucideIcons.eyeOff
                                : LucideIcons.eye,
                            color: AppPallete.gradient1,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),

                      SizedBox(height: 32),

                      // Login button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: _isLoading
                            ? Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppPallete.gradient1,
                                      AppPallete.gradient2
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                ),
                              )
                            : GlowingButton(
                                text: "Sign In",
                                onPressed: login,
                              ),
                      ),

                      SizedBox(height: 24),

                      // Divider with text
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 1,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    AppPallete.textColor.withOpacity(0.3),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              "OR",
                              style: GoogleFonts.lato(
                                color: AppPallete.textColor.withOpacity(0.6),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Container(
                              height: 1,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    AppPallete.textColor.withOpacity(0.3),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: 24),

                      // Google Sign-In button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: _buildGoogleSignInButton(),
                      ),

                      SizedBox(height: 32),

                      // Sign up link
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            PageRouteBuilder(
                              pageBuilder:
                                  (context, animation, secondaryAnimation) =>
                                      const RegisterPage(),
                              transitionsBuilder: (context, animation,
                                  secondaryAnimation, child) {
                                return FadeTransition(
                                    opacity: animation, child: child);
                              },
                            ),
                          );
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              vertical: 12, horizontal: 24),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppPallete.gradient1.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: RichText(
                            text: TextSpan(
                              style: GoogleFonts.lato(
                                fontSize: 16,
                                color: AppPallete.textColor,
                              ),
                              children: [
                                TextSpan(text: "Don't have an account? "),
                                TextSpan(
                                  text: "Sign Up",
                                  style: TextStyle(
                                    color: AppPallete.gradient1,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: 16),

                      // Debug button (for testing)
                      if (kDebugMode)
                        GestureDetector(
                          onTap: _createTestAccount,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                                vertical: 8, horizontal: 16),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.orange.withOpacity(0.5),
                                width: 1,
                              ),
                            ),
                            child: Text(
                              "Create Test Account",
                              style: GoogleFonts.lato(
                                fontSize: 12,
                                color: Colors.orange,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),

                      SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStyledTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppPallete.gradient1.withOpacity(0.1),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        style: GoogleFonts.lato(
          color: AppPallete.textColor,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: AppPallete.gradient1, size: 20),
          suffixIcon: suffixIcon,
          labelStyle: GoogleFonts.lato(
            color: AppPallete.gradient1,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          hintStyle: GoogleFonts.lato(
            color: AppPallete.textColor.withOpacity(0.5),
            fontSize: 14,
          ),
          filled: true,
          fillColor: Colors.white.withOpacity(0.9),
          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: AppPallete.gradient1.withOpacity(0.2),
              width: 1.5,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: AppPallete.gradient1,
              width: 2,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: AppPallete.errorColor,
              width: 2,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleSignInButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppPallete.gradient1.withOpacity(0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: _isLoading ? null : _signInWithGoogle,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  LucideIcons.chrome,
                  color: AppPallete.gradient1,
                  size: 24,
                ),
                SizedBox(width: 12),
                Text(
                  "Continue with Google",
                  style: GoogleFonts.lato(
                    color: AppPallete.textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
