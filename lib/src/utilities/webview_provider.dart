import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class LogtoWebview extends StatefulWidget {
  final Future<Uri> Function() getUrl;
  final String signInCallbackUri;
  final Color? primaryColor;
  final Color? backgroundColor;
  final Widget? title;

  const LogtoWebview({
    Key? key,
    required this.getUrl,
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

  late final Future<Uri> url;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) WebView.platform = AndroidWebView();
    url = widget.getUrl();
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
            FutureBuilder<Uri>(
                future: url,
                builder: (context, snapshot) {
                  if (snapshot.hasData) {
                    return WebView(
                      initialUrl: snapshot.requireData.toString(),
                      onPageFinished: (url) {
                        if (_loading && mounted) {
                          setState(() {
                            _loading = false;
                          });
                        }
                      },
                      zoomEnabled: false,
                      backgroundColor: widget.backgroundColor,
                      onWebViewCreated: (controller) =>
                          webViewController = controller,
                      navigationDelegate: _interceptNavigation,
                      javascriptMode: JavascriptMode.unrestricted,
                    );
                  }
                  return const SizedBox();
                }),
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
