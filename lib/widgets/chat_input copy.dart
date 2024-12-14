// lib/widgets/chat_input.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../providers/chat_provider.dart';
import '../screens/voice_input_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:typed_data';
import 'dart:convert';

class ImageData {
  final String path;        // 用於移動端
  final Uint8List? bytes;   // 用於web端
  final String fileName;    // 檔案名稱

  ImageData({
    required this.path,
    this.bytes,
    required this.fileName,
  });
}

class ChatInput extends StatefulWidget {
  final ScrollController scrollController;  // 新增

  const ChatInput({
    super.key,
    required this.scrollController,  // 新增
  });

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isComposing = false;
List<ImageData> _selectedImages = [];
  bool _showImagePicker = false;
  bool _isSearchEnabled = false;
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;

  // 判斷是否為桌面平台
  bool get _isDesktop {
    if (kIsWeb) return true;  // Web 版本視為桌面
    return !Platform.isIOS && !Platform.isAndroid;  // 非移動平台視為桌面
  }

  @override
  void initState() {
    super.initState();
    
    // 只在桌面版本自動獲得焦點
    if (_isDesktop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusNode.requestFocus();
      });
    }

    _focusNode.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _rotationAnimation = Tween<double>(
      begin: 0,
      end: 0.525,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

Future<void> _handleMicPressed() async {
  var status = await Permission.microphone.status;
  debugPrint('Current microphone permission status: $status');

  // 检查权限状态
  if (status.isGranted) {
    _showVoiceInputScreen();
    return;
  }

  if (status.isPermanentlyDenied) {
    // 用户永久拒绝了权限，显示对话框引导用户去设置中开启权限
    if (!mounted) return;
    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要麥克風權限'),
        content: const Text('請在設置中開啟麥克風權限以使用語音功能'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('前往設置'),
          ),
        ],
      ),
    );

    if (shouldOpenSettings == true) {
      await openAppSettings();
      // 等待用户从设置页面返回
      status = await Permission.microphone.status;
      if (status.isGranted && mounted) {
        _showVoiceInputScreen();
      }
    }
    return;
  }

  // 首次请求权限或之前被拒绝
  status = await Permission.microphone.request();
  debugPrint('Microphone permission request result: $status');

  if (status.isGranted) {
    if (!mounted) return;
    _showVoiceInputScreen();
  } else {
    if (!mounted) return;
    // 显示权限被拒绝的提示
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('需要麥克風權限才能使用語音功能'),
        backgroundColor: Colors.red,
        action: SnackBarAction(
          label: '設置',
          textColor: Colors.white,
          onPressed: () async {
            await openAppSettings();
            // 等待用户从设置页面返回
            status = await Permission.microphone.status;
            if (status.isGranted && mounted) {
              _showVoiceInputScreen();
            }
          },
        ),
      ),
    );
  }
}

void _showVoiceInputScreen() {
  showGeneralDialog(
    context: context,
    pageBuilder: (context, animation1, animation2) => const VoiceInputScreen(),
    transitionBuilder: (context, animation1, animation2, child) {
      return FadeTransition(
        opacity: animation1,
        child: child,
      );
    },
  );
}

@override
Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Column(
      children: [
        if (_selectedImages.isNotEmpty)
          Container(
            height: 100,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedImages.length,
              itemBuilder: (context, index) {
                return Stack(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      margin: const EdgeInsets.only(left: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                          width: 1,
                        ),
                      ),
child: ClipRRect(
  borderRadius: BorderRadius.circular(8),
child: kIsWeb
  ? Image.memory(
      _selectedImages[index].bytes!,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('Error loading image: $error');  // 改用 error 而不是 e
        return Container(
          width: 100,
          height: 100,
          color: isDarkMode ? Colors.grey[850] : Colors.grey[200],
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                color: Colors.grey[400],
                size: 32,
              ),
              const SizedBox(height: 4),
              Text(
                '無法載入',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    )
  : Image.file(
      File(_selectedImages[index].path),
      fit: BoxFit.cover,
    ),
),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: GestureDetector(
                        onTap: () => _removeImage(index),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.black : Colors.white,
            border: Border(
              top: BorderSide(
                color: isDarkMode ? Colors.grey[850]! : Colors.grey[200]!,
                width: 1,
              ),
            ),
          ),
          child: Column(
            children: [
              SafeArea(
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        constraints: const BoxConstraints(
                          maxWidth: 700, // 设置最大宽度限制
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.add,
                                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                              ),
                              onPressed: () {
                                setState(() {
                                  _showImagePicker = !_showImagePicker;
                                });
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.language,
                                color: _isSearchEnabled
                                    ? const Color(0xFF007AFF)
                                    : (isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                              ),
                              onPressed: () {
                                setState(() {
                                  _isSearchEnabled = !_isSearchEnabled;
                                });
                              },
                            ),
Expanded(
  child: RawKeyboardListener(
    focusNode: FocusNode(),
    onKey: (event) {
      if (event is RawKeyDownEvent) {
        if (event.logicalKey == LogicalKeyboardKey.enter) {
          // 如果按下 Shift，允許 TextField 自然換行
          if (event.isShiftPressed) {
            return;
          }
          
          // 檢查是否正在輸入中文
          if (_controller.value.composing.isValid) {
            return;
          }
          
          // 有內容且不是在輸入中文時才發送
          if (_isComposing) {
            _handleSubmitOrStop();
          }
          return;  // 直接返回來阻止默認行為
        }
      }
    },
    child: TextField(
      controller: _controller,
      focusNode: _focusNode,
      onTap: () {
        final chatProvider = Provider.of<ChatProvider>(context, listen: false);
        if (chatProvider.messages.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (widget.scrollController.hasClients) {
              widget.scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
        }
      },
      onChanged: (text) {
        setState(() {
          _isComposing = text.isNotEmpty || _selectedImages.isNotEmpty;
        });
      },
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      maxLines: 6,
      minLines: 1,
      decoration: InputDecoration(
        hintText: _isSearchEnabled ? '搜尋問題...' : '輸入訊息...',
        hintStyle: TextStyle(
          color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: isDarkMode ? Colors.grey[850] : Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        isDense: true,
        isCollapsed: false,
      ),
      style: TextStyle(
        color: isDarkMode ? Colors.white : Colors.black,
      ),
    ),
  ),
),
                            IconButton(
                              icon: Icon(
                                Icons.mic,
                                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                              ),
                              onPressed: _handleMicPressed,
                            ),
                            Consumer<ChatProvider>(
                              builder: (context, chatProvider, child) {
                                final bool canSubmit = _isComposing || chatProvider.isGenerating;
                                return IconButton(
                                  icon: AnimatedBuilder(
                                    animation: _animationController,
                                    builder: (context, child) {
                                      return Icon(
                                        chatProvider.isGenerating ? Icons.stop : Icons.send,
                                        color: canSubmit
                                            ? const Color(0xFF007AFF)
                                            : (isDarkMode ? Colors.grey[600] : Colors.grey[400]),
                                      );
                                    },
                                  ),
                                  onPressed: canSubmit ? _handleSubmitOrStop : null,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    Center(
                      child: Container(
                        constraints: const BoxConstraints(
                          maxWidth: 700, // 和输入框保持一致的宽度
                        ),
                        padding: const EdgeInsets.only(top: 2, bottom: 0),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'ChatNLM 可能會發生錯誤。請謹慎評估。',
                            style: TextStyle(
                              color: isDarkMode ? Colors.grey[600] : Colors.grey[500],
                              fontSize: 12,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                    if (_showImagePicker)
                      Center(
                        child: Container(
                          constraints: const BoxConstraints(
                            maxWidth: 700, // 和输入框保持一致的宽度
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              TextButton.icon(
                                icon: Icon(
                                  Icons.photo_library,
                                  color: isDarkMode ? Colors.white : Colors.black,
                                ),
                                label: Text(
                                  '相簿',
                                  style: TextStyle(
                                    color: isDarkMode ? Colors.white : Colors.black,
                                  ),
                                ),
                                onPressed: () => _pickImage(ImageSource.gallery),
                              ),
                              TextButton.icon(
                                icon: Icon(
                                  Icons.camera_alt,
                                  color: isDarkMode ? Colors.white : Colors.black,
                                ),
                                label: Text(
                                  '相機',
                                  style: TextStyle(
                                    color: isDarkMode ? Colors.white : Colors.black,
                                  ),
                                ),
                                onPressed: () => _pickImage(ImageSource.camera),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
}

// 在 ChatInput 类中修改 _pickImage 方法
void _pickImage(ImageSource source) async {
  try {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: source,
      imageQuality: 80,
    );

    if (image != null) {
      if (kIsWeb) {
        // Web平台：读取图片数据为bytes
        final bytes = await image.readAsBytes();
        setState(() {
          _selectedImages.add(ImageData(
            path: image.name, // Web平台使用文件名
            bytes: bytes,     // 保存图片数据
            fileName: image.name,
          ));
          _isComposing = true;
          _showImagePicker = false;
        });
      } else {
        // 移动端：使用文件路径
        setState(() {
          _selectedImages.add(ImageData(
            path: image.path,
            fileName: image.name,
          ));
          _isComposing = true;
          _showImagePicker = false;
        });
      }
    }
  } catch (e) {
    debugPrint('Error picking image: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择图片时发生错误：$e')),
      );
    }
  }
}

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      _isComposing = _selectedImages.isNotEmpty || _controller.text.isNotEmpty;
    });
  }

  void _handleSubmitOrStop() {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    
    if (chatProvider.isGenerating) {
      chatProvider.stopGeneration();
      _animationController.reverse();
    } else {
      if (!_isComposing) return;
      _handleSubmitted(_controller.text);
      _animationController.forward();
    }
  }
void _handleSubmitted(String text) {
  if (!_isComposing) return;
  
  final message = text.replaceAll('\n', '\n\n');
  final List<String> images = [];
  final int imageCount = _selectedImages.length;

  // 準備圖片數據
  for (var img in _selectedImages) {
    if (kIsWeb) {
      final base64String = base64.encode(img.bytes!);
      images.add('data:image/png;base64,$base64String');
    } else {
      images.add(img.path);
    }
  }

  // 如果有圖片，顯示進度指示器
  if (imageCount > 0) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: false, // 防止用戶關閉
      builder: (BuildContext context) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.grey[900] : Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isDarkMode ? Colors.blue[300]! : Colors.blue,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.image,
                        size: 16,
                        color: isDarkMode ? Colors.white70 : Colors.grey[600],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "圖片上傳中",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "$imageCount 張圖片處理中",
                        style: TextStyle(
                          fontSize: 13,
                          color: isDarkMode ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 清空輸入並發送消息
  _controller.clear();
  _focusNode.unfocus();

  Future.delayed(const Duration(milliseconds: 400), () async {
    if (!mounted) return;

    // 發送消息
    await Provider.of<ChatProvider>(context, listen: false)
        .sendMessage(
          message, 
          images: images.isNotEmpty ? images : null,
          useSearch: _isSearchEnabled,
        );
    
    // 發送完成後再關閉進度指示器和清空圖片
    if (imageCount > 0 && mounted) {
      Navigator.of(context).pop();
      setState(() {
        _selectedImages.clear();
        _isComposing = false;
        _showImagePicker = false;
      });
    } else {
      setState(() {
        _selectedImages.clear();
        _isComposing = false;
        _showImagePicker = false;
      });
    }

    // 如果是桌面端，重新獲取焦點
    if (_isDesktop && mounted) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  });
}

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    _animationController.dispose();
    super.dispose();
  }
}