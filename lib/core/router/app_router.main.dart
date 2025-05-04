part of 'app_router.dart';

/// The main route of the app.
/// This route is used to navigate to the main screen of the app.

final rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();
final routeObserver = RouteObserver<PageRoute>();

final router = GoRouter(
  observers: [routeObserver],
  navigatorKey: rootNavigatorKey,
  debugLogDiagnostics: true,
  initialLocation: '/',

  /// The routes of the app.
  routes: [
    /// "/" is the main route of the app.
    /// This route is used to navigate to the main screen of the app.
    GoRoute(
      path: '/',
      // redirect: (context, state) {},
      // builder: (context, state) {},
    ),

    /// "/Login" is the login route of the app.
    /// This route is used to navigate to the login screen of the app.
    // GoRoute(
    //   path: '/Login',
    //   builder: (context, state) {
    //     return const LoginScreen();
    //   },
    // ),

    /// Verify OTP
    // GoRoute(
    //   path: VerifyOtpScreen.path,
    //   builder: (context, state) {
    //     final extras = state.extra as Map<String, dynamic>?;
    //     final phone = extras?['phone'] as String;
    //     final countryCode = extras?['countryCode'] as String;

    //     return BlocProvider(
    //       create: (context) => sl<AuthCubit>(),
    //       child: VerifyOtpScreen(
    //         phone: phone,
    //         countryCode: countryCode,
    //       ),
    //     );
    //   },
    // ),

    /// ShellRoute
    /// This route is used to navigate to the main screen of the app.
    ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) {
          return ShellScreen();
        },

        /// The routes of the app.
        routes: [
          /// Home Route
          GoRoute(
            path: "/home",
          ),

          /// Scan Route
          GoRoute(
            path: "/scan",
          ),

          /// Profile Route
          GoRoute(
            path: "/profile",
          ),
        ])
  ],
);
