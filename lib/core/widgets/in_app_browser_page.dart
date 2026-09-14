import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../constants/campus_urls.dart';
import '../theme/app_theme.dart';

/// 应用内浏览器：通知原文、教务页等在 App 内打开。
class InAppBrowserPage extends StatefulWidget {
  const InAppBrowserPage({
    super.key,
    required this.initialUrl,
    this.title,
  });

  final String initialUrl;
  final String? title;

  @override
  State<InAppBrowserPage> createState() => _InAppBrowserPageState();
}

class _InAppBrowserPageState extends State<InAppBrowserPage> {
  InAppWebViewController? _controller;
  double _progress = 0;
  late String _title;

  @override
  void initState() {
    super.initState();
    _title = widget.title ?? '浏览';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: () => _controller?.reload(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_progress < 1)
            LinearProgressIndicator(
              value: _progress <= 0 ? null : _progress,
              minHeight: 2,
              backgroundColor: Colors.transparent,
            ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                mediaPlaybackRequiresUserGesture: true,
                userAgent: CampusUrls.userAgent,
                supportZoom: true,
              ),
              onWebViewCreated: (c) => _controller = c,
              onProgressChanged: (c, p) => setState(() => _progress = p / 100),
              onTitleChanged: (c, title) {
                if (title != null && title.trim().isNotEmpty) {
                  setState(() => _title = title.trim());
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
