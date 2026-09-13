import 'package:flutter/material.dart';

/// The one loading indicator every screen's `FutureBuilder` shows while its
/// data is still in flight - a shared widget so "loading" always looks and
/// behaves the same, instead of each screen wiring its own
/// `CircularProgressIndicator`.
class REmindLoadingState extends StatelessWidget {
  const REmindLoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}
