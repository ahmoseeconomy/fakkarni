import 'package:flutter/material.dart';

import 'config.dart';
import 'screens/widgets/admin_ui.dart';
import 'theme/tokens.dart';

/// اللوحة من غير `--dart-define` — بتقول اللي ناقص بالنص، ما بتحاولش
/// تتصل، وما بتقعش.
class MissingConfigScreen extends StatelessWidget {
  const MissingConfigScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: F.pageGround,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(F.s20),
            child: SizedBox(
              width: 420,
              child: AdminPanel(text: AdminConfig.missingMessage),
            ),
          ),
        ),
      );
}
