import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/store.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final store = await AppStore.load();
  runApp(V2TunApp(store: store));
}

class V2TunApp extends StatelessWidget {
  const V2TunApp({super.key, required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return StoreScope(
      store: store,
      child: Builder(builder: (context) {
        final s = StoreScope.of(context);
        return MaterialApp(
          title: 'V2-TUN',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(s.settings.accent, Brightness.dark),
          darkTheme: buildTheme(s.settings.accent, Brightness.dark),
          themeMode: ThemeMode.dark,
          // Text scale is clamped so a huge system font size cannot break layouts.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: MediaQuery.of(context).textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15),
            ),
            child: child!,
          ),
          home: const Shell(),
        );
      }),
    );
  }
}
