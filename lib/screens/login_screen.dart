import 'package:flutter/material.dart';
import 'dart:async';
import '../utils/ui_helpers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/local_auth.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import 'home_screen.dart';
import '../widgets/auth_header.dart';
import 'package:local_auth/local_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController(); // only used for registration
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController(); // only used for registration
  final AuthService _auth = AuthService();
  bool _loading = false;
  bool _isRegister = false; // toggle between login / register modes
  String? _emailError;
  String? _passwordError;
  bool _obscurePassword = true;
  bool _obscureConfirm = true; // registration field
  String? _inlineError;
  Timer? _inlineErrorTimer;
  final LocalAuthentication auth = LocalAuthentication();
  bool _biometricEnabled = false;
  bool _hasLocalAccount =
      false; // track if we have any saved accounts for biometric login

  @override
  void initState() {
    super.initState();
    try {
      final box = Hive.box('settings');
      _biometricEnabled =
          box.get('biometric_enabled', defaultValue: false) as bool;
    } catch (_) {
      _biometricEnabled = false;
    }
    // Check if we already have any accounts stored locally.  This is used to
    // decide whether biometric login should even be offered.
    _refreshHasLocalAccount();
  }

  void _showError(Object e) {
    final msg = _auth.friendlyError(e);
    _displayError(msg);
    debugPrint('LoginScreen._showError: $e');
  }

  void _displayError(String message) {
    // show inline banner
    if (mounted) {
      setState(() => _inlineError = message);
    }
    // Note: do not show a SnackBar here to avoid duplicate error messages;
    // the inline banner at the bottom of the form is the primary error UI.

    // auto-clear inline banner after a short delay (cancel previous timer)
    _inlineErrorTimer?.cancel();
    _inlineErrorTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _inlineError = null);
    });
  }

  @override
  void dispose() {
    _inlineErrorTimer?.cancel();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  /// Loads the accounts box and updates [_hasLocalAccount].
  Future<void> _refreshHasLocalAccount() async {
    try {
      final box = await Hive.openBox('accounts');
      if (mounted) {
        setState(() {
          _hasLocalAccount = box.isNotEmpty;
        });
      }
    } catch (_) {
      // ignore errors here; treat as no accounts
      if (mounted) {
        setState(() {
          _hasLocalAccount = false;
        });
      }
    }
  }

  Future<void> _authenticate() async {
    try {
      bool authenticated = await auth.authenticate(
        localizedReason: 'Please authenticate to proceed',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
        // useErrorDialogs is removed in v3, handled by plugin
      );
      debugPrint('Biometric authentication result: $authenticated');
      if (authenticated) {
        // Check if we have any accounts stored locally
        if (!_hasLocalAccount) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'No local account stored for biometric login. Please sign in manually.',
                ),
              ),
            );
          }
          return;
        }

        // Auto-login with saved account
        try {
          // dump raw box contents for debugging
          final box = await Hive.openBox('accounts');
          final accountsMap = box.toMap();
          debugPrint('accounts box map: $accountsMap');
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('accounts: $accountsMap')));
          }

          final emails = await LocalAuth.getSavedEmails();
          debugPrint('Saved emails: $emails');
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('emails list: $emails')));
          }
          if (emails.isEmpty) {
            debugPrint('No saved credentials for biometric auto-login');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Biometric success but no saved account. Please sign in manually.',
                  ),
                ),
              );
            }
            return;
          }

          final email = emails.first; // Use the first saved account
          final password = await LocalAuth.getPlainPassword(email);
          debugPrint(
            'Retrieved password for $email: ${password != null ? 'yes' : 'no'}',
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('password present: ${password != null}')),
            );
          }
          if (password != null) {
            // verify local credentials first
            bool credsOk = false;
            try {
              credsOk = await LocalAuth.verifyCredentials(email, password);
            } catch (vErr) {
              debugPrint('Local verify error: $vErr');
            }
            debugPrint('Local credentials valid: $credsOk');

            // attempt firebase login (may fail offline)
            try {
              debugPrint('Attempting Firebase sign-in for $email');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Signing in with $email')),
                );
              }
              await _auth.signInWithEmail(email, password);
              debugPrint('Firebase sign-in completed');
            } catch (signErr) {
              debugPrint('Firebase sign-in error: $signErr');
              // continue; offline fallback below
            }

            User? u = FirebaseAuth.instance.currentUser;
            debugPrint('Immediate currentUser after sign-in: ${u?.uid}');

            if (u == null && credsOk) {
              debugPrint('Offline fallback: using local credentials');
            }

            if (u != null || credsOk) {
              final displayEmail = u?.email ?? email;
              debugPrint('Navigation to HomeScreen for user $displayEmail');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Signed in as $displayEmail')),
                );
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => HomeScreen()),
                  (route) => false,
                );
              }
              return;
            }
          } else {
            debugPrint('Password for saved email was null');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Saved password missing.')),
              );
            }
          }
        } catch (e) {
          debugPrint('Auto-login failed: $e');
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Auto-login exception: $e')));
          }
        }
        // If auto-login failed or was incomplete, just show success message
        debugPrint('Auto-login failed, showing success message');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Biometric authentication successful'),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Biometric authentication failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Biometric authentication failed: $e')),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (mounted) {
      setState(() {
        _loading = true;
        _emailError = null;
        _passwordError = null;
      });
    }

    if (_isRegister) {
      // registration flow
      debugPrint(
        'LoginScreen._submit: attempt register for ${_emailCtrl.text.trim()}',
      );

      // set a flag so the global AuthGate won't react to the temporary
      // sign-in that occurs during account creation.  Without this we often
      // see the home screen flash briefly before the explicit sign-out below
      // kicks in, which was confusing to testers.
      AuthService.suppressAuthGate = true;

      try {
        final cred = await _auth.registerWithEmail(
          _emailCtrl.text.trim(),
          _passCtrl.text,
        );
        final u = cred.user;
        if (u == null) {
          throw FirebaseAuthException(
            code: 'user-creation-failed',
            message: 'User creation returned no user object',
          );
        }
        // create firestore profile and save local account
        try {
          final uid = u.uid;
          await FirestoreService.set('users/$uid', {
            'email': _emailCtrl.text.trim(),
            'role': 'user',
            'displayName': _usernameCtrl.text.trim(),
            'username': _usernameCtrl.text.trim(),
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          });
          debugPrint('Created Firestore profile for user $uid');
          await LocalAuth.saveAccount(
            email: _emailCtrl.text.trim(),
            username: _usernameCtrl.text.trim(),
            password: _passCtrl.text,
          );
          debugPrint('Saved account to Hive for offline login');
          // ensure biometric button is enabled after first registration
          _refreshHasLocalAccount();
        } catch (e) {
          debugPrint('Profile/local save error: $e');
        }
        // sign out so user can login
        try {
          await _auth.signOut();
        } catch (_) {}
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account created. Please sign in.')),
        );
        // flip back to login mode and clear fields
        if (mounted) {
          setState(() {
            _isRegister = false;
            _usernameCtrl.clear();
            _confirmCtrl.clear();
          });
        }
      } catch (e) {
        _showError(e);
      } finally {
        if (mounted) setState(() => _loading = false);
        // always clear the suppression flag no matter what happened
        AuthService.suppressAuthGate = false;
      }
      return;
    }

    // --- login flow continues here ---
    debugPrint(
      'LoginScreen._submit: attempt sign-in for ${_emailCtrl.text.trim()}',
    );
    try {
      await _auth.signInWithEmail(_emailCtrl.text.trim(), _passCtrl.text);
      debugPrint('LoginScreen._submit: signInWithEmail returned');
      User? u = FirebaseAuth.instance.currentUser;
      debugPrint('Signed in user immediate check: uid=${u?.uid}');

      if (u == null) {
        // Sometimes the Firebase SDK hasn't propagated the currentUser immediately.
        // Wait a short while and poll for the auth state before failing.
        debugPrint(
          'currentUser was null immediately after sign-in, waiting for propagation...',
        );
        bool found = false;
        for (var i = 0; i < 6; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          u = FirebaseAuth.instance.currentUser;
          debugPrint('poll $i -> uid=${u?.uid}');
          if (u != null) {
            found = true;
            break;
          }
        }

        if (!found) {
          debugPrint(
            'Sign-in returned but currentUser remained null after polling',
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Signed in but no user object found.'),
              ),
            );
          }
        }
      }

      if (u != null) {
        debugPrint(
          'Sign-in successful, navigating to Home: ${u.email} uid=${u.uid}',
        );
        if (!mounted) return;
        try {
          // Ensure Firestore profile exists and load it (basic check).
          try {
            final uid = u.uid;
            final doc = await FirestoreService.getDocument('users/$uid');
            if (doc == null || !doc.exists) {
              // Create a default profile if missing
              await FirestoreService.set('users/$uid', {
                'email': u.email,
                'role': 'user',
                'displayName': u.displayName ?? '',
                'createdAt': DateTime.now().toUtc().toIso8601String(),
              });
              debugPrint('Created missing Firestore profile for $uid');
            } else {
              debugPrint('Loaded Firestore profile for $uid');
            }
          } catch (profileErr) {
            debugPrint('Error loading/creating Firestore profile: $profileErr');
          }

          if (!mounted) return;
          // Guard against using context after async gaps.
          final messenger = ScaffoldMessenger.of(context);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Signed in as ${u.email}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.secondary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              duration: const Duration(seconds: 3),
            ),
          );

          // Persist account locally for offline sign-in convenience.
          try {
            final username = u.displayName ?? _emailCtrl.text.split('@').first;
            await LocalAuth.saveAccount(
              email: _emailCtrl.text.trim(),
              username: username,
              password: _passCtrl.text,
            );
            debugPrint('Saved account to Hive for offline login');
            // debug contents of the box after saving
            final box = await Hive.openBox('accounts');
            final map = box.toMap();
            debugPrint('accounts box after save: $map');
            // now update the flag so the biometric button appears
            _refreshHasLocalAccount();
          } catch (localErr) {
            debugPrint('Failed to save local account after sign-in: $localErr');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('failed saving local account: $localErr'),
                ),
              );
            }
          }

          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => HomeScreen()),
            (route) => false,
          );
        } catch (navErr) {
          debugPrint('Navigation error after sign-in: $navErr');
        }
      }
    } catch (e) {
      final errText = e.toString();
      final isPigeonTypeError =
          errText.contains('Pigeon') || errText.contains('is not a subtype of');
      debugPrint(
        'Sign-in exception: ${isPigeonTypeError ? 'platform/plugin type error' : e}',
      );

      // Some platforms/plugins return raw credential errors like
      // "The supplied auth credential is malformed or expired" — map those
      // to a friendly password error and show it under the password field.
      final errLower = errText.toLowerCase();
      if (errLower.contains('supplied auth credential') ||
          errLower.contains('malformed') ||
          errLower.contains('expired') ||
          errLower.contains('invalid credential')) {
        if (mounted) {
          setState(() {
            _passwordError = 'Incorrect password.';
            _inlineError = null;
            _emailError = null;
          });
        }
        return;
      }

      // If the platform layer threw a pigeon/type error but the sign-in actually
      // succeeded on the backend, FirebaseAuth.instance.currentUser may be set.
      final uCheck = FirebaseAuth.instance.currentUser;
      if (uCheck != null) {
        debugPrint(
          'Sign-in produced platform error, but currentUser is present uid=${uCheck.uid}. Navigating to Home.',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Signed in as ${uCheck.email}')));
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => HomeScreen()),
          (route) => false,
        );
        return;
      }

      // Offline fallback: verify against locally stored credentials (Hive)
      try {
        final ok = await LocalAuth.verifyCredentials(
          _emailCtrl.text.trim(),
          _passCtrl.text,
        );
        if (ok) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Signed in offline as ${_emailCtrl.text.trim()}'),
            ),
          );
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => HomeScreen()),
            (route) => false,
          );
          return;
        }
      } catch (localErr) {
        debugPrint('Offline credential check failed: $localErr');
      }

      // Specific guidance for pigeon/type cast errors (common plugin mismatch symptom)

      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'user-not-found':
            if (mounted) {
              setState(() {
                _emailError = 'No account found for this email.';
                _inlineError = null;
                _passwordError = null;
              });
            }
            break;
          case 'wrong-password':
            if (mounted) {
              setState(() {
                _passwordError = 'Incorrect password.';
                _inlineError = null;
                _emailError = null;
              });
            }
            break;
          case 'network-request-failed':
            if (mounted) {
              setState(() {
                _emailError = null;
                _passwordError = null;
              });
            }
            _displayError(
              'Network error. Please check your internet connection.',
            );
            break;
          default:
            _showError(e);
        }
      } else {
        final dialogMsg = isPigeonTypeError
            ? 'Internal platform error occurred during sign-in. This can happen when Firebase plugins are out of sync. Try running flutter pub upgrade and rebuild the app.'
            : e.toString();

        if (mounted) {
          _displayError(dialogMsg);
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _google() async {
    if (mounted) setState(() => _loading = true);
    try {
      final cred = await _auth.signInWithGoogle();
      User? u = FirebaseAuth.instance.currentUser ?? cred?.user;
      if (u != null) {
        // Ensure Firestore profile exists (same as email flow)
        try {
          final uid = u.uid;
          final doc = await FirestoreService.getDocument('users/$uid');
          if (doc == null || !doc.exists) {
            await FirestoreService.set('users/$uid', {
              'email': u.email,
              'role': 'user',
              'displayName': u.displayName ?? '',
              'createdAt': DateTime.now().toUtc().toIso8601String(),
            });
            debugPrint('Created missing Firestore profile for $uid');
          }
        } catch (profileErr) {
          debugPrint('Error loading/creating Firestore profile: $profileErr');
        }

        if (!mounted) return;
        showAppSnackBar(context, 'Signed in as ${u.email}');
        // Save local account for offline/biometric access
        try {
          final username = u.displayName ?? u.email!.split('@').first;
          await LocalAuth.saveAccount(
            email: u.email!,
            username: username,
            password: '', // No password for Google accounts
          );
          debugPrint('Saved Google account locally for offline access');
          _refreshHasLocalAccount();
        } catch (localErr) {
          debugPrint('Failed to save Google account locally: $localErr');
        }
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (e is AccountExistsWithDifferentCredential) {
        await _showLinkDialog(e.email);
      } else {
        final msg = e.toString();
        if (msg.contains('Google Sign-In not configured')) {
          // more actionable message
          _displayError(
            'Google Sign-In is not configured. '
            'Please see the project README/GOOGLE_SIGNIN.md for setup instructions.',
          );
        } else {
          _showError(e);
        }
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showLinkDialog(String email) async {
    final pwCtrl = TextEditingController();
    final res = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Link accounts'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'An account exists with the same email. Enter password to link Google to it:',
            ),
            SizedBox(height: 8),
            TextField(
              controller: pwCtrl,
              obscureText: true,
              decoration: InputDecoration(labelText: 'Password'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Link'),
          ),
        ],
      ),
    );

    if (res == true) {
      if (mounted) setState(() => _loading = true);
      try {
        await _auth.linkPendingCredentialWithEmailPassword(email, pwCtrl.text);
      } catch (e) {
        _showError(e);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // helper for consistent input decoration
    InputDecoration inputDecoration({
      required String hint,
      String? errorText,
      Widget? suffixIcon,
    }) {
      return InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14),
        errorText: errorText,
        errorStyle: const TextStyle(color: Colors.red, fontSize: 12),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 16,
          horizontal: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: cs.onSurface.withAlpha((0.06 * 255).round()),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: cs.onSurface.withAlpha((0.06 * 255).round()),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.primary),
        ),
        suffixIcon: suffixIcon,
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: BouncingScrollPhysics(),
          child: Column(
            children: [
              // Top curved header (compact)
              AuthHeader(
                title: 'Drug Store',
                subtitle: _isRegister
                    ? 'Create a new account'
                    : 'Welcome back! please login to your account',
                height: 160,
                titleFontSize: 27,
                subtitleFontSize: 15,
              ),

              SizedBox(height: 70),

              // Primary login button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Card(
                  color: theme.cardColor,
                  elevation: theme.cardTheme.elevation ?? 6,
                  shape:
                      theme.cardTheme.shape ??
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                  child: Padding(
                    padding: const EdgeInsets.all(18.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // (Moved) inline error banner will be shown below form fields
                          // Toggle row (Login / Register) – switch form in place
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // login button
                              GestureDetector(
                                onTap: () {
                                  if (_isRegister) {
                                    setState(() {
                                      _isRegister = false;
                                      _emailError = null;
                                      _passwordError = null;
                                      _inlineError = null;
                                      _usernameCtrl.clear();
                                      _confirmCtrl.clear();
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: !_isRegister
                                        ? cs.primary
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'Log In',
                                    style: TextStyle(
                                      color: !_isRegister
                                          ? cs.onPrimary
                                          : cs.onSurface.withAlpha(
                                              (0.7 * 255).round(),
                                            ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // register button
                              GestureDetector(
                                onTap: () {
                                  if (!_isRegister) {
                                    setState(() {
                                      _isRegister = true;
                                      _emailError = null;
                                      _passwordError = null;
                                      _inlineError = null;
                                      _usernameCtrl.clear();
                                      _confirmCtrl.clear();
                                    });
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _isRegister
                                        ? cs.primary
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'Register',
                                    style: TextStyle(
                                      color: _isRegister
                                          ? cs.onPrimary
                                          : cs.onSurface.withAlpha(
                                              (0.7 * 255).round(),
                                            ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          SizedBox(height: 18),

                          // if we're registering show username first
                          if (_isRegister) ...[
                            TextFormField(
                              controller: _usernameCtrl,
                              decoration: inputDecoration(hint: 'Username'),
                              style: const TextStyle(fontSize: 14),
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Please enter a username.';
                                }
                                return null;
                              },
                            ),
                          ],
                          SizedBox(height: 12),
                          // Email
                          TextFormField(
                            controller: _emailCtrl,
                            decoration: inputDecoration(
                              hint: 'Email',
                              errorText: _emailError,
                            ),
                            style: const TextStyle(fontSize: 14),
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Please enter your email.';
                              }
                              final email = v.trim();
                              final re = RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+$");
                              if (!re.hasMatch(email)) {
                                return 'Please enter a valid email address.';
                              }
                              return null;
                            },
                          ),

                          SizedBox(height: 12),

                          // (Forgot password link moved below login button)

                          // Password
                          TextFormField(
                            controller: _passCtrl,
                            decoration: InputDecoration(
                              hintText: 'Password',
                              hintStyle: TextStyle(fontSize: 12),
                              errorText: _passwordError,
                              errorStyle: const TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 8,
                                horizontal: 12,
                              ),
                              suffixIcon: AnimatedRotation(
                                turns: _obscurePassword ? 0.0 : 0.5,
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeInOut,
                                child: IconButton(
                                  tooltip: _obscurePassword
                                      ? 'Show password'
                                      : 'Hide password',
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.65),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                              ),
                            ),
                            style: TextStyle(fontSize: 12),
                            obscureText: _obscurePassword,
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return 'Please enter your password.';
                              }
                              if (v.length < 6) {
                                return 'Password must be at least 6 characters.';
                              }
                              final hasDigit = RegExp(r"[0-9]").hasMatch(v);
                              if (!hasDigit) {
                                return 'Password must include a number.';
                              }
                              return null;
                            },
                          ),

                          // confirm password (shown only when registering)
                          if (_isRegister) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _confirmCtrl,
                              decoration: inputDecoration(
                                hint: 'Confirm password',
                                suffixIcon: AnimatedRotation(
                                  turns: _obscureConfirm ? 0.0 : 0.5,
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeInOut,
                                  child: IconButton(
                                    tooltip: _obscureConfirm
                                        ? 'Show password'
                                        : 'Hide password',
                                    icon: Icon(
                                      _obscureConfirm
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: cs.onSurface.withAlpha(
                                        (0.65 * 255).round(),
                                      ),
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscureConfirm = !_obscureConfirm;
                                      });
                                    },
                                  ),
                                ),
                              ),
                              style: const TextStyle(fontSize: 14),
                              obscureText: _obscureConfirm,
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return 'Please confirm your password.';
                                }
                                if (v != _passCtrl.text) {
                                  return 'Passwords do not match.';
                                }
                                return null;
                              },
                            ),
                          ],

                          SizedBox(height: 18),

                          // Primary action button
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _loading ? null : _submit,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: cs.primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    elevation: 4,
                                  ),
                                  child: _loading
                                      ? SizedBox(
                                          height: 16,
                                          width: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Text(
                                          _isRegister
                                              ? 'Create account'
                                              : 'Log In',
                                          style: TextStyle(fontSize: 14),
                                        ),
                                ),
                              ),
                            ],
                          ),

                          SizedBox(height: 12),

                          // Biometric authentication button (only on login, enabled in settings)
                          if (!_isRegister && _biometricEnabled)
                            Center(
                              child: IconButton(
                                onPressed: _authenticate,
                                icon: const Icon(Icons.fingerprint, size: 32),
                                tooltip: 'Biometric login',
                                style: IconButton.styleFrom(
                                  backgroundColor: theme.colorScheme.secondary,
                                  foregroundColor:
                                      theme.colorScheme.onSecondary,
                                  padding: const EdgeInsets.all(16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),

                          SizedBox(height: 12),

                          // Forgot password (only on login)
                          if (!_isRegister)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: () =>
                                    Navigator.pushNamed(context, '/forgot'),
                                child: Text('Forgot password?'),
                              ),
                            ),

                          Center(
                            child: Text(
                              'or',
                              style: TextStyle(color: Colors.black54),
                            ),
                          ),

                          SizedBox(height: 12),

                          // Social icons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(width: 12),
                              GestureDetector(
                                onTap: _google,
                                child: CircleAvatar(
                                  backgroundColor: const Color.fromARGB(
                                    255,
                                    206,
                                    220,
                                    223,
                                  ),
                                  child: Image.asset(
                                    'assets/icons/google.png',
                                    height: 22,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          SizedBox(height: 12),

                          // inline error message below the form fields
                          if (_inlineError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.error,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _inlineError!,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.white70,
                                      ),
                                      onPressed: () =>
                                          setState(() => _inlineError = null),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          TextButton(
                            onPressed: () =>
                                Navigator.pushNamed(context, '/privacy'),
                            child: Text(
                              'Privacy policy · Term of service',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
