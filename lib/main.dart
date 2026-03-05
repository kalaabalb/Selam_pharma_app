import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'models/medicine.dart';
import 'models/report.dart';
import 'providers/pharmacy_provider.dart';
import 'services/sync_service.dart';
import 'providers/theme_provider.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/forgot_password_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/contact_screen.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';
// utils/ui_helpers replaced by direct ScaffoldMessenger usage in async handlers

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Only load .env on desktop platforms where the file is accessible
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    try {
      await dotenv.load(fileName: ".env");
    } catch (e) {
      debugPrint('Warning: Could not load .env: $e');
    }
  }
  try {
    await Firebase.initializeApp();
  } catch (e) {
    // On some desktop platforms firebase_core isn't supported, so we
    // swallow initialization errors. Runtime features will check for
    // FirebaseAuth.instance etc before use.
    debugPrint('Firebase.initializeApp failed: $e');
  }
  await Hive.initFlutter();
  Hive.registerAdapter(MedicineAdapter());
  Hive.registerAdapter(ReportAdapter());

  // chat box is used to cache conversation while the app is running.  We
  // clear it on startup so that any messages left over from a previous run
  // are discarded; this satisfies the requirement that the data only live
  // "until the app is closed".  Messages added during the session are
  // written to the box and will survive navigation between pages.
  final chatBox = await Hive.openBox('chat');
  await chatBox.clear();

  // Start background sync between Hive, Firestore and Cloudinary
  // We'll create and initialize SyncService here so it starts after Firebase init.
  SyncService? syncService;
  try {
    syncService = SyncService();
    // Initialize SyncService in background so we don't block the UI startup.
    syncService.init().catchError((e) {
      debugPrint('Warning: SyncService failed to init: $e');
    });
  } catch (e) {
    debugPrint('Warning: SyncService failed to init: $e');
  }

  final settingsBox = await Hive.openBox('settings');
  // initialize notifications early
  try {
    await NotificationService.instance.initialize();
  } catch (e) {
    debugPrint('NotificationService init failed: $e');
  }

  final navigatorKey = GlobalKey<NavigatorState>();
  // provide navigatorKey to NotificationService so notification taps can navigate
  NotificationService.instance.navigatorKey = navigatorKey;

  runApp(
    MyApp(
      settingsBox: settingsBox,
      syncService: syncService,
      navigatorKey: navigatorKey,
    ),
  );
}

class MyApp extends StatelessWidget {
  final Box settingsBox;
  final SyncService? syncService;
  final GlobalKey<NavigatorState> navigatorKey;

  const MyApp({
    super.key,
    required this.settingsBox,
    this.syncService,
    required this.navigatorKey,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeProvider(settingsBox)),
        ChangeNotifierProvider(
          create: (context) => PharmacyProvider()..initBoxes(),
        ),
        // Provide SyncService so other widgets can access it if needed.
        Provider<SyncService?>.value(value: syncService),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Drugo',
            navigatorKey: navigatorKey,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: themeProvider.themeMode,
            routes: {
              '/home': (_) => HomeScreen(),
              '/login': (_) => LoginScreen(),
              '/register': (_) => RegisterScreen(),
              '/forgot': (_) => ForgotPasswordScreen(),
              // make contact screen available for named navigation
              ContactScreen.routeName: (_) => const ContactScreen(),
            },
            builder: (context, child) {
              final sync = Provider.of<SyncService?>(context);
              return StreamBuilder<String?>(
                stream: sync?.errorStream,
                builder: (context, snap) {
                  final raw = snap.data;
                  if (raw == null) return child!;

                  final err = raw.split('\n').first;
                  final lowered = err.toLowerCase();
                  final isPermDenied =
                      lowered.contains('permission') &&
                      lowered.contains('denied');

                  // Sanitize messages shown to users. Log raw error for debugging.
                  debugPrint('SyncService reported error: $err');
                  final message = isPermDenied
                      ? 'Firestore permission denied — your account cannot access this data. Check your Firestore rules or sign out.'
                      : 'Sync error — check your network connection and Firestore rules. You can dismiss this message.';

                  return Column(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      MaterialBanner(
                        content: Text(message),
                        backgroundColor: Colors.red.shade700,
                        actions: [
                          if (isPermDenied) ...[
                            TextButton(
                              onPressed: () async {
                                final navigator = Navigator.of(context);
                                final messenger = ScaffoldMessenger.of(context);
                                try {
                                  await AuthService().signOut();
                                  navigator.pushNamedAndRemoveUntil(
                                    '/login',
                                    (route) => false,
                                  );
                                } catch (e) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('Sign out failed: $e'),
                                      backgroundColor: Colors.red.shade700,
                                    ),
                                  );
                                }
                              },
                              child: const Text(
                                'Sign out',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                          TextButton(
                            onPressed: () {
                              sync?.clearError();
                            },
                            child: const Text(
                              'Dismiss',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      Expanded(child: child!),
                    ],
                  );
                },
              );
            },
            onGenerateRoute: (settings) {
              // Animated transitions for a few important named routes.
              if (settings.name == '/auth') {
                return PageRouteBuilder(
                  settings: settings,
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const AuthGate(),
                  transitionDuration: const Duration(milliseconds: 600),
                  transitionsBuilder:
                      (_, animation, secondaryAnimation, child) {
                        final fade = CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeInOut,
                        );
                        final offset =
                            Tween<Offset>(
                              begin: const Offset(0, 0.08),
                              end: Offset.zero,
                            ).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOut,
                              ),
                            );
                        return FadeTransition(
                          opacity: fade,
                          child: SlideTransition(
                            position: offset,
                            child: child,
                          ),
                        );
                      },
                );
              }

              // Use the same smooth fade+slide for login/register route pushes.
              if (settings.name == '/login' || settings.name == '/register') {
                final Widget page = settings.name == '/login'
                    ? LoginScreen()
                    : RegisterScreen();
                return PageRouteBuilder(
                  settings: settings,
                  pageBuilder: (context, animation, secondaryAnimation) => page,
                  transitionDuration: const Duration(milliseconds: 420),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                        final curve = CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeInOut,
                        );
                        final offset = Tween<Offset>(
                          begin: const Offset(0, 0.06),
                          end: Offset.zero,
                        ).animate(curve);
                        return FadeTransition(
                          opacity: curve,
                          child: SlideTransition(
                            position: offset,
                            child: child,
                          ),
                        );
                      },
                );
              }

              return null;
            },
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = snapshot.data;

        // If the login/register screen has indicated that it is performing a
        // registration flow, we want to continue showing the login UI even if
        // a user object briefly appears.  This prevents a flash of HomeScreen
        // when a newly-created account is automatically signed in and shortly
        // afterwards signed out again.
        if (AuthService.suppressAuthGate) {
          return LoginScreen();
        }

        if (user == null) return LoginScreen();

        return FutureBuilder<bool>(
          future: _verifyUser(user),
          builder: (context, verifySnap) {
            if (verifySnap.connectionState == ConnectionState.waiting) {
              return Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (verifySnap.data == true) return HomeScreen();
            return LoginScreen();
          },
        );
      },
    );
  }

  Future<bool> _verifyUser(User user) async {
    try {
      await user.reload();
      final u = FirebaseAuth.instance.currentUser;
      debugPrint('AuthGate._verifyUser: reload done uid=${u?.uid}');
      if (u == null) {
        debugPrint('AuthGate._verifyUser: currentUser is null');
        return false;
      }
      if (u.isAnonymous) {
        debugPrint('AuthGate._verifyUser: anonymous user -> signing out');
        await FirebaseAuth.instance.signOut();
        return false;
      }
      // Force-refresh ID token to ensure server-side account state (deleted/disabled)
      try {
        await u.getIdToken(true);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found' ||
            e.code == 'user-disabled' ||
            e.code == 'invalid-user-token') {
          debugPrint(
            'AuthGate._verifyUser: idToken refresh failed (${e.code}) — signing out',
          );
          await FirebaseAuth.instance.signOut();
          return false;
        }
        rethrow;
      }
      // Some platforms may report empty providerData briefly after sign-in.
      // Avoid signing the user out immediately; accept the user if a valid uid
      // exists and is not anonymous.
      if (u.providerData.isEmpty) {
        debugPrint(
          'AuthGate._verifyUser: providerData empty but uid present, accepting user',
        );
        return true;
      }
      return true;
    } catch (e) {
      final errText = e.toString();
      final isPigeonTypeError =
          errText.contains('Pigeon') || errText.contains('is not a subtype of');
      if (isPigeonTypeError) {
        debugPrint(
          'AuthGate._verifyUser: plugin/platform type error (Pigeon/type-cast)',
        );
      } else {
        debugPrint('AuthGate._verifyUser: exception $e');
      }
      final u = FirebaseAuth.instance.currentUser;
      if (isPigeonTypeError && u != null && !u.isAnonymous) {
        debugPrint(
          'AuthGate._verifyUser: plugin type error but currentUser present; accepting user uid=${u.uid}',
        );
        return true;
      }
      await FirebaseAuth.instance.signOut();
      return false;
    }
  }
}
