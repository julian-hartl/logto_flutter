import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class LogtoWebview extends StatefulWidget {
  final Uri url;
  final String signInCallbackUri;
  final Color? primaryColor;
  final Color? backgroundColor;
  final Widget? title;

  const LogtoWebview({
    Key? key,
    required this.url,
    required this.signInCallbackUri,
    this.primaryColor,
    this.backgroundColor,
    this.title,
  }) : super(key: key);

  @override
  State<LogtoWebview> createState() => _LogtoWebView();
}

class _LogtoWebView extends State<LogtoWebview> {
  WebViewController? webViewController;

  @override
  void initState() {
    if (Platform.isAndroid) WebView.platform = AndroidWebView();
    super.initState();
  }

  NavigationDecision _interceptNavigation(NavigationRequest request) {
    if (!mounted) return NavigationDecision.prevent;
    if (request.url.startsWith(widget.signInCallbackUri)) {
      Navigator.pop(context, request.url);
      return NavigationDecision.prevent;
    }

    return NavigationDecision.navigate;
  }

  bool _loading = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: widget.title ?? const Text('Sign In'),
        leading: BackButton(
          onPressed: () async {
            final canGoBack = (await webViewController?.canGoBack()) ?? false;
            if (canGoBack) {
              webViewController!.goBack();
            } else {
              if (mounted) {
                Navigator.pop(context);
              }
            }
          },
        ),
        backgroundColor: widget.primaryColor,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            WebView(
              initialUrl: widget.url.toString(),
              onPageFinished: (url) {
                if (_loading && mounted) {
                  setState(() {
                    _loading = false;
                  });
                }
              },
              zoomEnabled: false,
              backgroundColor: widget.backgroundColor,
              onWebViewCreated: (controller) => webViewController = controller,
              navigationDelegate: _interceptNavigation,
              javascriptMode: JavascriptMode.unrestricted,
            ),
            if (_loading)
              Center(
                child: CircularProgressIndicator(
                  color: widget.primaryColor,
                ),
              )
          ],
        ),
      ),
    );
  }
}
