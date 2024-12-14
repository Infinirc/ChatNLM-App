// lib/widgets/chat_message.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../models/message.dart';
import '../models/search_result.dart';
import 'markdown_content.dart';
import '../providers/chat_provider.dart';
import 'package:provider/provider.dart';
import '../config/env.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';
import 'dart:convert';
import '../providers/conversation_provider.dart';
import '../widgets/message_rating.dart';
class _CopyButton extends StatefulWidget {
  final String content;

  const _CopyButton({
    required this.content,
  });

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isCopied = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) {
            _controller.reverse();
            setState(() {
              _isCopied = false;
            });
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _copyContent() {
    Clipboard.setData(ClipboardData(text: widget.content));
    setState(() {
      _isCopied = true;
    });
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          _isCopied ? Icons.check : Icons.copy,
          key: ValueKey<bool>(_isCopied),
          size: 16,
          color: Colors.grey[400],
        ),
      ),
      onPressed: _copyContent,
      tooltip: '複製內容',
    );
  }
}

class ImageViewer extends StatelessWidget {
  final String imagePath;
  final bool isNetworkImage;

  const ImageViewer({
    super.key,
    required this.imagePath,
    this.isNetworkImage = false,
  });

@override
Widget build(BuildContext context) {
  Widget imageWidget;
  
  // 處理 base64 格式圖片
  if (imagePath.startsWith('data:image')) {
    try {
      final startIndex = imagePath.indexOf(',') + 1;
      final bytes = base64.decode(imagePath.substring(startIndex));
      imageWidget = Image.memory(
        bytes,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Error loading base64 image in viewer: $error');
          return _buildErrorWidget();
        },
      );
    } catch (e) {
      debugPrint('Error decoding base64 image in viewer: $e');
      return _buildErrorWidget();
    }
  }
  // 處理網絡圖片
  else if (isNetworkImage) {
    imageWidget = Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return Image.network(
          '${Env.conversationApiUrl}$imagePath',
          headers: {
            'x-user-id': authProvider.userId ?? '',
          },
          errorBuilder: (context, error, stackTrace) {
            debugPrint('Error loading network image in viewer: $error');
            return _buildErrorWidget();
          },
        );
      }
    );
  }
  // 處理 Web 平台的圖片
  else if (kIsWeb) {
    imageWidget = Consumer<ChatProvider>(
      builder: (context, chatProvider, child) {
        final imageData = chatProvider.getImageData(imagePath);
        if (imageData != null) {
          return Image.memory(
            imageData.bytes,
            errorBuilder: (context, error, stackTrace) {
              debugPrint('Error loading web image in viewer: $error');
              return _buildErrorWidget();
            },
          );
        }
        return _buildErrorWidget();
      },
    );
  }
  // 處理本地文件
  else {
    imageWidget = Consumer<ChatProvider>(
      builder: (context, chatProvider, child) {
        try {
          return Image.file(
            File(imagePath),
            errorBuilder: (context, error, stackTrace) {
              // 如果本地文件讀取失敗，嘗試從 Provider 獲取緩存數據
              final imageData = chatProvider.getImageData(imagePath);
              if (imageData != null) {
                return Image.memory(
                  imageData.bytes,
                  errorBuilder: (context, error, stackTrace) {
                    debugPrint('Error loading cached image in viewer: $error');
                    return _buildErrorWidget();
                  },
                );
              }
              debugPrint('Error loading local image in viewer: $error');
              return _buildErrorWidget();
            },
          );
        } catch (e) {
          debugPrint('Error handling local image in viewer: $e');
          return _buildErrorWidget();
        }
      },
    );
  }

  return GestureDetector(
    onTap: () => Navigator.of(context).pop(),
    child: Container(
      color: Colors.black.withOpacity(0.9),
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: imageWidget,
            ),
          ),
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(
                Icons.close,
                color: Colors.white,
                size: 30,
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildErrorWidget() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.error_outline,
          color: Colors.grey[400],
          size: 48,
        ),
        const SizedBox(height: 16),
        Text(
          '無法載入圖片',
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

class ChatMessage extends StatelessWidget {
  static const String nlmLogo = 'assets/images/logo/NLM.png';
  static const String nlmGenLogo = 'assets/images/logo/NLM-gen.gif';
  
  final Message message;

  const ChatMessage({
    super.key,
    required this.message,
  });

  bool _isNetworkImage(String path) {
    return path.startsWith('/uploads/');
  }

  // 新增方法：顯示搜尋結果
void _showSearchResults(BuildContext context) {
  final isDarkMode = Theme.of(context).brightness == Brightness.dark;
  
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(context),
            child: Container(
              color: Colors.transparent,
            ),
          ),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (context, scrollController) => GestureDetector(
            onTap: () {},
            child: Container(
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.grey[900] : Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.grey[700] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        Text(
                          '引用',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.grey[200] : Colors.grey[800],
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: isDarkMode ? Colors.grey[800] : Colors.grey[300],
                  ),
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: message.searchResults?.length ?? 0,
                      itemBuilder: (context, index) {
                        final result = message.searchResults![index];
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: isDarkMode ? Colors.grey[850] : Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _launchUrl(result.url),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ListTile(
                                    leading: Container(
                                      width: 36,
                                      height: 36,
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: _isSpecialEngine(result.engine)
                                        ? _buildCustomIcon(result.engine)
                                        : Image.network(
                                            result.favicon ?? '',
                                            width: 20,
                                            height: 20,
                                            errorBuilder: (context, error, stackTrace) {
                                              debugPrint('Error loading favicon: $error for URL: ${result.favicon}');
                                              return Icon(
                                                Icons.public,
                                                size: 20,
                                                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                              );
                                            },
                                          ),
                                    ),
                                    title: Text(
                                      result.title,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: isDarkMode ? Colors.white : Colors.grey[800],
                                      ),
                                    ),
                                    subtitle: Text(
                                      Uri.parse(result.url).host,
                                      style: TextStyle(
                                        color: Colors.blue[isDarkMode ? 300 : 600],
                                        fontSize: 12,
                                      ),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.open_in_new),
                                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                      onPressed: () => _launchUrl(result.url),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                    child: Text(
                                      result.content,
                                      style: TextStyle(
                                        color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

// 添加這些輔助方法
bool _isSpecialEngine(String engine) {
  return ['langchain', 'nvidia', 'proxmox'].contains(engine.toLowerCase());
}

Widget _buildCustomIcon(String engine) {
  IconData iconData;
  Color color;
  
  switch (engine.toLowerCase()) {
    case 'langchain':
      iconData = Icons.auto_awesome;
      color = Colors.purple;
      break;
    case 'nvidia':
      iconData = Icons.memory;
      color = Colors.green;
      break;
    case 'proxmox':
      iconData = Icons.storage;
      color = Colors.orange;
      break;
    default:
      iconData = Icons.public;
      color = Colors.blue;
  }

  return Icon(
    iconData,
    color: color,
    size: 20,
  );
}
// 添加 URL 啟動方法
Future<void> _launchUrl(String urlString) async {
  final uri = Uri.parse(urlString);
  if (await canLaunchUrl(uri)) {
    await launchUrl(
      uri,
      mode: LaunchMode.inAppWebView,
      webViewConfiguration: const WebViewConfiguration(
        enableJavaScript: true,
        enableDomStorage: true,
      ),
    );
  } else {
    debugPrint('Could not launch $urlString');
  }
}

  // 新增方法：建構來源按鈕
Widget _buildSourceButton(BuildContext context) {
  if (message.searchResults == null || message.searchResults!.isEmpty) {
    return const SizedBox.shrink();
  }

  final isDarkMode = Theme.of(context).brightness == Brightness.dark;
  final topResults = message.searchResults!.take(3).toList();

  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () => _showSearchResults(context),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: isDarkMode ? Colors.grey[700]! : Colors.grey[400]!),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '資料來源',
              style: TextStyle(
                color: isDarkMode ? Colors.white : Colors.grey[800],
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            ...topResults.map((result) {
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _buildSourceIcon(context, result, isDarkMode),
              );
            }).toList(),
          ],
        ),
      ),
    ),
  );
}

// 添加輔助方法來建構源圖標
Widget _buildSourceIcon(BuildContext context, SearchResult result, bool isDarkMode) {
  IconData iconData;
  Color color;
  
  // 先設置預設圖標和顏色
  switch (result.engine.toLowerCase()) {
    case 'nvidia':
      iconData = Icons.memory;
      color = Colors.green;
      break;
    case 'proxmox':
      iconData = Icons.storage;
      color = Colors.orange;
      break;
    case 'cloud':
      iconData = Icons.cloud;
      color = Colors.blue;
      break;
    case 'web':
      iconData = Icons.web;
      color = Colors.purple;
      break;
    default:
      iconData = Icons.public;
      color = Colors.blue;
  }

  final uri = Uri.parse(result.url);
  final favicon = result.favicon ?? 'https://www.google.com/s2/favicons?domain=${uri.host}';
  
  return Container(
    width: 20,
    height: 20,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image.network(
        favicon,
        width: 20,
        height: 20,
        errorBuilder: (context, error, stackTrace) => Icon(
          iconData,
          size: 16,
          color: isDarkMode ? color.withOpacity(0.8) : color,
        ),
      ),
    ),
  );
}

  void _showImageViewer(BuildContext context, String imagePath, bool isNetworkImage) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (BuildContext context, _, __) {
          return ImageViewer(
            imagePath: imagePath,
            isNetworkImage: isNetworkImage,
          );
        },
      ),
    );
  }

// 修改 _buildImageWidget 方法
Widget _buildImageWidget(String imagePath, bool isNetworkImage) {
  // 檢查是否為 base64 圖片
  if (imagePath.startsWith('data:image')) {
    try {
      // 解析 base64 圖片
      final startIndex = imagePath.indexOf(',') + 1;
      final bytes = base64Decode(imagePath.substring(startIndex));
      return Image.memory(
        bytes,
        width: 200,
        height: 200,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Error loading base64 image: $error');
          return _buildErrorBox();
        },
      );
    } catch (e) {
      debugPrint('Error decoding base64 image: $e');
      return _buildErrorBox();
    }
  }

  // 網絡圖片處理
  if (isNetworkImage) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return Image.network(
          '${Env.conversationApiUrl}$imagePath',
          width: 200,
          height: 200,
          fit: BoxFit.cover,
          headers: {
            'x-user-id': authProvider.userId ?? '',
          },
          errorBuilder: (context, error, stackTrace) {
            debugPrint('Error loading network image: $error');
            return _buildErrorBox();
          },
        );
      }
    );
  } 
  
  // Web 平台處理
  if (kIsWeb) {
    return Consumer<ChatProvider>(
      builder: (context, chatProvider, child) {
        final imageData = chatProvider.getImageData(imagePath);
        if (imageData != null) {
          return Image.memory(
            imageData.bytes,
            width: 200,
            height: 200,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              debugPrint('Error loading web image: $error');
              return _buildErrorBox();
            },
          );
        }
        return _buildErrorBox();
      },
    );
  }
  
  // 移動平台處理本地文件
  try {
    return Image.file(
      File(imagePath),
      width: 200,
      height: 200,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        // 如果本地文件讀取失敗，嘗試從 Provider 獲取緩存數據
        return Consumer<ChatProvider>(
          builder: (context, chatProvider, child) {
            final imageData = chatProvider.getImageData(imagePath);
            if (imageData != null) {
              return Image.memory(
                imageData.bytes,
                width: 200,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  debugPrint('Error loading cached image: $error');
                  return _buildErrorBox();
                },
              );
            }
            debugPrint('Error loading local image: $error');
            return _buildErrorBox();
          },
        );
      },
    );
  } catch (e) {
    debugPrint('Error handling local image: $e');
    return _buildErrorBox();
  }
}

// 添加一個輔助方法來建立錯誤提示框
Widget _buildErrorBox() {
  return SizedBox(
    width: 200,
    height: 200,
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            color: Colors.grey[400],
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            '無法載入圖片',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 12,
            ),
          ),
        ],
      ),
    ),
  );
}

@override
Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
if (!message.isUser)
  Container(
    margin: const EdgeInsets.only(right: 8.0),
    child: CircleAvatar(
      backgroundColor: isDarkMode ? Colors.grey[800] : Colors.grey[200],
      child: ClipOval(
        child: message.isComplete 
          ? Image.asset(
              'assets/images/logo/NLM.png',
              width: 40,
              height: 40,
              fit: BoxFit.cover,
            )
          : Image.asset(
              'assets/images/logo/NLM-gen.gif',
              width: 40,
              height: 40,
              fit: BoxFit.cover,
            ),
      ),
    ),
  ),
          Expanded(
            child: Column(
              crossAxisAlignment: message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!message.isUser && message.searchResults?.isNotEmpty == true)
                  _buildSourceButton(context),
                if (message.images != null && message.images!.isNotEmpty)
                  Container(
                    height: 200,
                    margin: const EdgeInsets.only(bottom: 8.0),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      // 添加 reverse: true 来反转列表方向
                      reverse: true,  // 添加这一行
                      itemCount: message.images!.length,
                      itemBuilder: (context, index) {
                        final imagePath = message.images![index]['url']!;
                        final isNetworkImage = _isNetworkImage(imagePath);
                        
                        return Padding(
                          // 修改 padding，从右边开始
                          padding: const EdgeInsets.only(left: 8.0),  // 改为 left padding
                          child: GestureDetector(
                            onTap: () => _showImageViewer(
                              context,
                              imagePath,
                              isNetworkImage,
                            ),
                            child: Hero(
                              tag: 'image_$imagePath',
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  width: 200,
                                  decoration: BoxDecoration(
                                    color: isDarkMode ? Colors.grey[850] : Colors.grey[100],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: _buildImageWidget(imagePath, isNetworkImage),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: message.isUser
                        ? (isDarkMode
                            ? const Color.fromARGB(255, 80, 80, 80) // 深色模式用戶消息背景
                            : const Color.fromARGB(255, 80, 80, 80)) // 淺色模式用戶消息背景
                        : (isDarkMode
                            ? const Color(0xFF1C1C1E) // 深色模式 AI 消息背景
                            : Colors.white), // 淺色模式 AI 消息背景
                    borderRadius: BorderRadius.circular(20.0),
                    border: (!message.isUser && !isDarkMode)
                        ? Border.all(
                            color: Colors.grey.withOpacity(0.2),
                            width: 1,
                          )
                        : null,
                    boxShadow: !isDarkMode
                        ? [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MarkdownContent(
                        content: message.content,
                        textColor: message.isUser || isDarkMode
                            ? Colors.white
                            : const Color(0xFF2C2C2E),  // 黑色文字用於淺色模式下的 AI 消息
                      ),
                      if (!message.isComplete) ...[
                        const SizedBox(height: 8),
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
if (!message.isUser) ...[
  const SizedBox(height: 4),
  Row(
    mainAxisAlignment: MainAxisAlignment.end,  // 確保在右邊
    mainAxisSize: MainAxisSize.max,  // 使用最大寬度
    children: [
      const Expanded(child: SizedBox()),  // 添加這行，將按鈕推到右邊
      Container(
        margin: const EdgeInsets.only(right: 8.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.contentVersions != null && message.contentVersions!.length > 1) ...[
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  icon: const Icon(Icons.chevron_left, size: 16),
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  onPressed: message.currentVersion > 0
                      ? () => Provider.of<ChatProvider>(context, listen: false)
                          .switchMessageVersion(message.id, message.currentVersion - 1)
                      : null,
                  splashRadius: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    maxWidth: 32,
                    minHeight: 32,
                    maxHeight: 32,
                  ),
                  tooltip: '上一個版本',
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  "${message.currentVersion + 1}/${message.contentVersions!.length}",
                  style: TextStyle(
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ),
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  icon: const Icon(Icons.chevron_right, size: 16),
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  onPressed: message.currentVersion < message.contentVersions!.length - 1
                      ? () => Provider.of<ChatProvider>(context, listen: false)
                          .switchMessageVersion(message.id, message.currentVersion + 1)
                      : null,
                  splashRadius: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    maxWidth: 32,
                    minHeight: 32,
                    maxHeight: 32,
                  ),
                  tooltip: '下一個版本',
                ),
              ),
            ],
            
            if (message.isComplete) ...[
              Consumer<ConversationProvider>(
                builder: (context, conversationProvider, _) {
                  return MessageRating(
                    message: message,
                    conversationId: conversationProvider.currentConversation?.id ?? '',
                  );
                },
              ),
            ],

            const SizedBox(width: 2),
            SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                icon: const Icon(Icons.refresh, size: 16),
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                onPressed: () => Provider.of<ChatProvider>(context, listen: false)
                    .regenerateResponse(message.id),
                splashRadius: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  maxWidth: 32,
                  minHeight: 32,
                  maxHeight: 32,
                ),
                tooltip: '重新生成回應',
              ),
            ),
            SizedBox(
              width: 32,
              height: 32,
              child: _CopyButton(content: message.content),
            ),
          ],
        ),
      ),
    ],
  ),
],
              ],
            ),
          ),
        ],
      ),
    );
  }
}