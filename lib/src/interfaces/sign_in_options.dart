import 'dart:ui';

import 'package:flutter/material.dart';

class SignInOptions {
  final Color? backgroundColor;
  final Color? primaryColor;
  final String redirectUri;
  final Widget? title;

  const SignInOptions({
    required this.redirectUri,
    this.backgroundColor,
    this.primaryColor,
    this.title,
  });
}
