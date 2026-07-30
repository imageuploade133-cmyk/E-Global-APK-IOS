import 'package:flutter/material.dart';

class WebviewLoader extends StatelessWidget {
  const WebviewLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.orange))),
    );
  }
}
