import 'package:flutter/material.dart';
import '../theme/text_styles.dart';

class TWCFooter extends StatelessWidget {
  const TWCFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Text('Powered by Third Wave Coffee', style: TWCTextStyles.footer, textAlign: TextAlign.center);
  }
}
