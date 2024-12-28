//lib/screens/chat_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/conversation_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/chat_input.dart';
import '../widgets/chat_message.dart';
import '../models/conversation.dart';
import '../widgets/streaming_text.dart'; 
import 'package:flutter_svg/flutter_svg.dart';
import '../screens/login_screen.dart';
class KeepAlive extends StatefulWidget {
  const KeepAlive({
    Key? key,
    required this.child,
  }) : super(key: key);

  final Widget child;

  @override
  State<KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }

  @override
  bool get wantKeepAlive => true;
}
class ChatScreen extends StatefulWidget {
  static const IconData add_comment_outlined = IconData(0xee41, fontFamily: 'MaterialIcons');
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  // 修改：分開聊天和對話列表的控制器
  final ScrollController _chatScrollController = ScrollController();
  final ScrollController _sidebarScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  
  bool _isLoading = false;
  bool _isLoadingMore = false;
  int _page = 1;
  final int _pageSize = 20;
  bool _isSidebarCollapsed = false;
  bool _previousShowSidebar = false;
  bool _isFirstLoad = true;
  
  // 添加此方法
  bool _shouldShowSidebar(BuildContext context) {
    return MediaQuery.of(context).size.width >= 1000;
  }

@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _loadInitialData();
    final showSidebar = _shouldShowSidebar(context);
    setState(() {
      _isSidebarCollapsed = !showSidebar;
      _previousShowSidebar = showSidebar;
      _isFirstLoad = false;
    });
  });
  
  // 確保滾動監聽器被正確添加
  _sidebarScrollController.addListener(_scrollListener);
}

@override
void didChangeDependencies() {
  super.didChangeDependencies();
  if (!_isFirstLoad) {
    final showSidebar = _shouldShowSidebar(context);
    if (showSidebar != _previousShowSidebar) {
      setState(() {
        _previousShowSidebar = showSidebar;
        if (!showSidebar) {
          // 視窗變窄時，先執行收合動畫
          _isSidebarCollapsed = true;
        }
      });

      if (showSidebar) {
        // 視窗變寬時，使用連續的兩步動畫
        setState(() {
          _isSidebarCollapsed = true;  // 先設置為收合狀態
        });
        
        // 等待極短時間後觸發展開動畫
        Future.delayed(const Duration(milliseconds: 10), () {
          if (mounted) {
            setState(() {
              _isSidebarCollapsed = false;  // 執行展開動畫
            });
          }
        });
      }
    }
  }
}
void _scrollListener() {
  if (!_sidebarScrollController.hasClients) return;
  
  final maxScroll = _sidebarScrollController.position.maxScrollExtent;
  final currentScroll = _sidebarScrollController.position.pixels;
  final loadThreshold = maxScroll - 200.0; // 減小閾值，使其更早觸發
  
  if (currentScroll >= loadThreshold) {
    final conversationProvider = Provider.of<ConversationProvider>(
      context, 
      listen: false
    );
    
    if (!conversationProvider.isLoadingMore && conversationProvider.hasMoreData) {
      debugPrint('Triggering load more conversations from scroll');
      conversationProvider.loadMoreConversations();
    }
  }
}
@override
void dispose() {
  _searchController.dispose();
  _sidebarScrollController.removeListener(_scrollListener);
  _sidebarScrollController.dispose();
  _chatScrollController.dispose();
  super.dispose();
}

  Future<void> _loadInitialData() async {
    final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    await conversationProvider.loadConversations();
    if (conversationProvider.conversations.isEmpty) {
      final conversation = await conversationProvider.createConversation('New Chat');
      await conversationProvider.setCurrentConversation(conversation);
    }
    await chatProvider.loadModels();
  }

Future<void> _loadMoreConversations() async {
  final conversationProvider = Provider.of<ConversationProvider>(
    context,
    listen: false,
  );
  
  if (!conversationProvider.hasMoreData || 
      conversationProvider.isLoadingMore) {
    return;
  }

  try {
    await conversationProvider.loadMoreConversations();
  } catch (e) {
    debugPrint('Error loading more conversations: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('載入更多對話失敗：$e')),
      );
    }
  }
}


Future<void> _createNewChat() async {
  if (_isLoading) return;

  // 檢查登入狀態
  final authProvider = context.read<AuthProvider>();
  if (authProvider.userId == null) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請先登入')),
      );
    }
    return;
  }

  // 檢查當前對話是否為空
  final chatProvider = Provider.of<ChatProvider>(context, listen: false);
  final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);
  
  // 如果當前對話是空的，直接返回不執行任何操作
  if (conversationProvider.currentConversation != null && 
      chatProvider.messages.isEmpty) {
    return;
  }

  // 先關閉抽屜
  if (mounted && Navigator.canPop(context)) {
    Navigator.pop(context);
  }

  setState(() => _isLoading = true);

  try {
    // 創建新對話
    await conversationProvider.createConversation('New Chat');
    // 清空現有消息
    await chatProvider.clearMessages();
    
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('創建對話失敗：$e')),
      );
    }
  } finally {
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }
}

  Future<void> _handleConversationTap(Conversation conversation) async {
    if (_isLoading) return;

    // 先關閉抽屜
    if (mounted && Navigator.canPop(context)) {
      Navigator.pop(context);
    }

    setState(() => _isLoading = true);
    
    try {
      final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      
      // 設置當前對話
      await conversationProvider.setCurrentConversation(conversation);
      // 清空並加載新消息
      await chatProvider.clearMessages();
      await chatProvider.loadConversationMessages(conversation.id);
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('載入對話失敗：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleDeleteConversation(String conversationId) async {
    if (_isLoading) return;
    
    setState(() => _isLoading = true);
    
    try {
      final conversationProvider = Provider.of<ConversationProvider>(context, listen: false);
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      
      await conversationProvider.deleteConversation(conversationId);
      
      if (conversationProvider.currentConversation?.id == conversationId) {
        await chatProvider.clearMessages();
      }
      


    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

@override
Widget build(BuildContext context) {
  final isDarkMode = Theme.of(context).brightness == Brightness.dark;
  final showSidebar = _shouldShowSidebar(context);

return Scaffold(
  resizeToAvoidBottomInset: true,
  appBar: !showSidebar ? AppBar(
    backgroundColor: isDarkMode ? Colors.black : Colors.white,
    elevation: 1,
    title: Consumer<ConversationProvider>(
      builder: (context, provider, child) {
        final conversation = provider.currentConversation;
        final conversationTitle = conversation?.title ?? 'ChatNLM';
        final isUpdating = provider.isTitleUpdating;
        return StreamingText(
          text: conversationTitle,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w500,
            color: isDarkMode ? Colors.white : Colors.black,
          ),
          maxLength: 20,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          streamEnabled: isUpdating,
        );
      },
    ),
    centerTitle: true,
    iconTheme: IconThemeData(
      color: isDarkMode ? Colors.white : Colors.black,
    ),


actions: [
  Consumer2<ChatProvider, ConversationProvider>(
    builder: (context, chatProvider, conversationProvider, child) {
      final hasMessages = chatProvider.messages.isNotEmpty;
      final hasConversations = conversationProvider.conversations.isNotEmpty;
      final bool canCreate = hasMessages || !hasConversations;
      
      return IconButton(
        icon: _isLoading ? 
          SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                isDarkMode ? Colors.white : Colors.black,
              ),
            ),
          ) : 
          Icon(
            ChatScreen.add_comment_outlined,  // 改用新的 icon
            color: canCreate
                ? (isDarkMode ? Colors.white : Colors.black)
                : (isDarkMode ? Colors.grey[700] : Colors.grey[400]),
          ),
        onPressed: _isLoading || !canCreate ? null : _createNewChat,
      );
    },
  ),
],
  ) : null,
drawer: !showSidebar ? Drawer(
  backgroundColor: isDarkMode ? Colors.black : Colors.white,
  child: SafeArea(
    child: _buildSidebarContent(context, isDarkMode, false),  // 傳入 false 表示這是抽屜模式
  ),
) : null,



    
    body: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 側邊欄
AnimatedContainer(
  duration: const Duration(milliseconds: 300),
  curve: Curves.easeInOutCubic,
  width: showSidebar ? (_isSidebarCollapsed ? 0 : 300) : 0,
  child: OverflowBox(
    maxWidth: 300,
    child: AnimatedSlide(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      offset: Offset(_isSidebarCollapsed ? -1 : 0, 0),
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          color: isDarkMode 
            ? const Color.fromARGB(255, 27, 27, 27)
            : const Color.fromARGB(255, 242, 242, 242),
          borderRadius: const BorderRadius.only(
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: _buildSidebarContent(context, isDarkMode, true),
      ),
    ),
  ),
),

      // 主要內容區域
Expanded(
  child: Container(
    color: isDarkMode ? Colors.black : Colors.white,
    child: Column(
      children: [
        // 寬螢幕模式的標題欄 - 保持全寬
        if (showSidebar)
          Container(
            height: kToolbarHeight,
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.black : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: isDarkMode ? Colors.grey[850]! : Colors.grey[200]!,
                  width: 1,
                ),
              ),
            ),
            
            child: Row(
              children: [
                IconButton(
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return RotationTransition(
                        turns: Tween<double>(
                          begin: _isSidebarCollapsed ? 0.5 : 0.0,
                          end: _isSidebarCollapsed ? 0.0 : 0.5,
                        ).animate(animation),
                        child: FadeTransition(
                          opacity: animation,
                          child: child,
                        ),
                      );
                    },
                    child: Icon(
                      _isSidebarCollapsed ? Icons.menu : Icons.menu_open,
                      key: ValueKey<bool>(_isSidebarCollapsed),
                      color: isDarkMode ? Colors.white : Colors.black,
                    ),
                  ),
                  onPressed: () {
                    setState(() {
                      _isSidebarCollapsed = !_isSidebarCollapsed;
                    });
                  },
                ),
                Expanded(
                  child: Consumer<ConversationProvider>(
                    builder: (context, provider, child) {
                      final conversation = provider.currentConversation;
                      final conversationTitle = conversation?.title ?? 'ChatNLM';
                      final isUpdating = provider.isTitleUpdating;
                      return Center(
                        child: Container(
                          constraints: const BoxConstraints(
                            maxWidth: 900,
                          ),
                          child: StreamingText(
                            text: conversationTitle,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                              color: isDarkMode ? Colors.white : Colors.black,
                            ),
                            maxLength: 20,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            streamEnabled: isUpdating,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        



Consumer<ChatProvider>(
 builder: (context, chatProvider, child) {
   return Container(
     height: 44,
     padding: const EdgeInsets.symmetric(horizontal: 16),
     decoration: BoxDecoration(
       color: isDarkMode ? Colors.black : Colors.white,
     ),
     child: Center(
       child: Container(
         constraints: const BoxConstraints(maxWidth: 900),
         child: Row(
           mainAxisAlignment: MainAxisAlignment.center,
           children: [
             DropdownButtonHideUnderline(
               child: Theme(
                 data: Theme.of(context).copyWith(
                   popupMenuTheme: PopupMenuThemeData(
                     shape: RoundedRectangleBorder(
                       borderRadius: BorderRadius.circular(8),
                     ),
                   ),
                 ),
                 child: DropdownButton<String>(
                   value: chatProvider.currentModel?.id,
                   icon: Row(
                     mainAxisSize: MainAxisSize.min,
                     children: [
                       const SizedBox(width: 8),
                       Icon(
                         Icons.expand_more_rounded,
                         color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                         size: 20,
                       ),
                     ],
                   ),
                   elevation: 4,
                   borderRadius: BorderRadius.circular(8),
                   dropdownColor: isDarkMode ? const Color(0xFF1C1C1E) : Colors.white,
                   menuMaxHeight: 300,
                   style: TextStyle(
                     color: isDarkMode ? Colors.white : Colors.black,
                     fontSize: 14,
                   ),
                   items: chatProvider.models.map((model) {
                     return DropdownMenuItem<String>(
                       value: model.id,
                       child: Row(
                         mainAxisSize: MainAxisSize.min,
                         children: [
                           Icon(
                             Icons.auto_awesome,
                             size: 14,
                             color: isDarkMode ? Colors.blue[400] : Colors.blue,
                           ),
                           const SizedBox(width: 6),
                           Container(
                             constraints: const BoxConstraints(maxWidth: 200),
                             child: Text(
                               model.id,
                               overflow: TextOverflow.ellipsis,
                             ),
                           ),
                         ],
                       ),
                     );
                   }).toList(),
                   onChanged: (String? modelId) {
                     if (modelId != null) {
                       final selectedModel = chatProvider.models
                           .firstWhere((model) => model.id == modelId);
                       chatProvider.setCurrentModel(selectedModel);
                     }
                   },
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




        // 聊天內容區域和 ChatInput
        Expanded(
          child: Column(
            children: [
              Expanded(
                child: Consumer<ChatProvider>(
                  builder: (context, chatProvider, child) {
                    return chatProvider.messages.isEmpty
                      ? Center(
                          child: ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: const [
                                Color(0xFF2D7CFF),
                                Color(0xFFB554FF),
                                Color(0xFFFF4F87),
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ).createShader(bounds),
                            child: const Text(
                              'HI, 你好！',
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                height: 1.5,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _chatScrollController,
                          reverse: true,
                          physics: const ClampingScrollPhysics(),
                          padding: EdgeInsets.only(
                            bottom: MediaQuery.of(context).padding.bottom + 8,
                            top: MediaQuery.of(context).viewPadding.top + 8,
                          ),
                          itemCount: chatProvider.messages.length,
                          itemBuilder: (context, index) {
                            final message = chatProvider.messages[index];
                            return Center(
                              child: Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 900,
                                ),
                                child: ChatMessage(message: message),
                              ),
                            );
                          },
                        );
                  },
                ),
              ),
              Center(
                child: Container(
                  constraints: const BoxConstraints(
                    maxWidth: 900,
                  ),
                  child: ChatInput(scrollController: _chatScrollController),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  ),
),
    ],
  ),

  );
}

// 提取側邊欄內容為獨立方法
Widget _buildSidebarContent(BuildContext context, bool isDarkMode, bool showSidebar) {
  return Column(
    children: [
      // Logo 容器修改
Container(
  padding: EdgeInsets.symmetric(
    vertical: showSidebar ? 16 : 3,  // 寬螢幕時使用更大的垂直內邊距
    horizontal: 16,
  ),
  decoration: BoxDecoration(
    border: Border(
      bottom: BorderSide(
        color: isDarkMode ? Colors.grey[850]! : Colors.grey[200]!,
        width: 0,
      ),
    ),
  ),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      SvgPicture.asset(
        isDarkMode
          ? 'assets/images/logo/Chat-dark.svg'
          : 'assets/images/logo/Chat-light.svg',
        height: 40,
        fit: BoxFit.contain,
      ),
      if (showSidebar)
        Consumer2<ChatProvider, ConversationProvider>(
          builder: (context, chatProvider, conversationProvider, child) {
            final hasMessages = chatProvider.messages.isNotEmpty;
            final hasConversations = conversationProvider.conversations.isNotEmpty;
            final bool canCreate = hasMessages || !hasConversations;
            
            return IconButton(
              icon: _isLoading ? 
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isDarkMode ? Colors.white : Colors.black,
                    ),
                  ),
                ) : 
                Icon(
                  ChatScreen.add_comment_outlined,
                  size: 24,
                  color: canCreate
                      ? (isDarkMode ? Colors.white : Colors.black)
                      : (isDarkMode ? Colors.grey[700] : Colors.grey[400]),
                ),
              onPressed: _isLoading || !canCreate ? null : _createNewChat,
            );
          },
        ),
    ],
  ),
),
      // 搜尋欄...
Padding(
  padding: EdgeInsets.only(
    top: showSidebar ? 4 : 16,     // 寬螢幕模式時減少頂部間距
    bottom: showSidebar ? 4 : 16,  // 寬螢幕模式時減少底部間距
    left: 16,
    right: 16,
  ),
  child: Container(
    decoration: BoxDecoration(
      color: isDarkMode 
        ? const Color.fromARGB(255, 74, 74, 74)
        : const Color.fromARGB(0, 23, 23, 23),
      borderRadius: BorderRadius.circular(10),
      border: isDarkMode 
        ? null 
        : Border.all(
            color: Colors.grey[300]!,
            width: 1,
          ),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
      children: [
        Icon(
          Icons.search,
          color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
          size: 20,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _searchController,
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black,
            ),
            decoration: InputDecoration(
              hintText: '搜尋',
              hintStyle: TextStyle(
                color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              fillColor: isDarkMode ? null : Colors.white,
              filled: !isDarkMode,
              isDense: true,
            ),
            onChanged: (value) {
              context.read<ConversationProvider>().setSearchQuery(value);
            },
          ),
        ),
        if (_searchController.text.isNotEmpty)
                IconButton(
                  icon: Icon(
                    Icons.close,
                    color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
                    size: 20,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    context.read<ConversationProvider>().setSearchQuery('');
                  },
                ),
            ],
          ),
        ),
      ),

      // 分隔線
      Divider(
        height: 1,
        color: isDarkMode ? Colors.grey[850] : Colors.grey[200],
      ),

      // 對話列表...
      Expanded(
        child: Consumer<ConversationProvider>(
          builder: (context, provider, child) {
            // 原有的對話列表代碼保持不變...
            if (provider.conversations.isEmpty) {
              return Center(
                child: Text(
                  provider.searchQuery.isEmpty ? '暫無對話記錄' : '無搜尋結果',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
              );
            }

            final groups = provider.getGroupedConversations();
            
            
return RefreshIndicator(
  onRefresh: () async {
    await provider.loadConversations();
  },
  color: isDarkMode ? Colors.white : Colors.black,
  backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
  child: ListView.builder(
    controller: showSidebar ? _sidebarScrollController : null,
    itemCount: groups.length + (provider.hasMoreData ? 1 : 0),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    physics: const AlwaysScrollableScrollPhysics(),
    cacheExtent: 1000,
    key: PageStorageKey(showSidebar ? 'sidebar_list' : 'drawer_list'),
    addAutomaticKeepAlives: true,
    addRepaintBoundaries: true,
    itemBuilder: (context, groupIndex) {
      // 處理底部加載指示器
      if (groupIndex == groups.length && provider.hasMoreData) {
        // 如果到達底部，自動觸發加載
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!provider.isLoadingMore) {
            provider.loadMoreConversations();
          }
        });

        return SizedBox(
          height: 60,
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                isDarkMode ? Colors.white : Colors.grey[600]!,
              ),
            ),
          ),
        );
      }

      final group = groups[groupIndex];
      // 其餘列表項渲染代碼保持不變...
return KeepAlive(
  key: ValueKey('group_${group.title}_$groupIndex'),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (groupIndex > 0)
        const SizedBox(height: 16),
      Padding(
        padding: const EdgeInsets.only(left: 16, top: 16, bottom: 8),
        child: Text(
          group.title,
          style: TextStyle(
            color: isDarkMode ? Colors.grey[600] : Colors.grey[500],
            fontSize: 13,
          ),
        ),
      ),
...group.conversations.map((conversation) {
  final isSelected = provider.currentConversation?.id == conversation.id;
  // 每個群組中的對話項添加群組索引，確保全局唯一
  return Material(
    // 使用組合鍵確保唯一性
    key: ValueKey('${group.title}_conversation_${conversation.id}'),
    color: Colors.transparent,
    child: ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      tileColor: isSelected
          ? (isDarkMode ? Colors.grey[900] : Colors.grey[100])
          : Colors.transparent,
      title: StreamingText(
        key: ValueKey('${group.title}_streaming_${conversation.id}'),
        text: conversation.title,
        style: TextStyle(
          color: isDarkMode ? Colors.white : Colors.black,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        maxLength: 25,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        streamEnabled: provider.isTitleUpdating && 
                    provider.currentConversation?.id == conversation.id,
      ),
      onTap: () => _handleConversationTap(conversation),
      trailing: IconButton(
        key: ValueKey('${group.title}_delete_${conversation.id}'),
        icon: Icon(
          Icons.delete_outline,
          color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
          size: 20,
        ),
        onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
                          title: Text(
                            '刪除對話',
                            style: TextStyle(
                              color: isDarkMode ? Colors.white : Colors.black,
                            ),
                          ),
                          content: Text(
                            '確定要刪除這個對話嗎？',
                            style: TextStyle(
                              color: isDarkMode ? Colors.white : Colors.black,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(
                                '取消',
                                style: TextStyle(
                                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _handleDeleteConversation(conversation.id);
                              },
                              child: const Text(
                                '刪除',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              );
            }).toList(),
          ],
        ),
      );
    },
  ),
);
          },
        ),
      ),

      // 試用模式按鈕
Consumer<AuthProvider>(
  builder: (context, authProvider, _) {
    if (!authProvider.isTrialMode) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ElevatedButton(
        onPressed: () async {
          final chatProvider = Provider.of<ChatProvider>(context, listen: false);
          await chatProvider.handleLogout();  // 使用新的處理登出方法
          await authProvider.logout();
          if (context.mounted) {
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (context) => const LoginScreen(),
              ),
              (route) => false,
            );
          }
        },
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: const Color.fromARGB(255, 107, 107, 107),
          minimumSize: const Size.fromHeight(40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: const Text('Login'),
      ),
    );
  },
),

      // 使用者資訊欄
      Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: isDarkMode ? Colors.grey[850]! : Colors.grey[200]!,
              width: 1,
            ),
          ),
        ),
        child: Consumer<AuthProvider>(
          builder: (context, authProvider, _) {
            final name = authProvider.userName ?? '使用者';
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: isDarkMode ? Colors.grey[800] : Colors.grey[300],
                child: Text(
                  name.substring(0, name.length > 2 ? 2 : 1).toUpperCase(),
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                name,
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black,
                  fontSize: 16,
                ),
              ),
              trailing: PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_horiz,
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                ),
                color: isDarkMode ? Colors.grey[900] : Colors.white,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'clear',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.delete_outline,
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                      title: Text(
                        '清除所有對話',
                        style: TextStyle(
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ),
                  if (!authProvider.isTrialMode) PopupMenuItem(
                    value: 'logout',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.logout,
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                      title: Text(
                        '登出',
                        style: TextStyle(
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ),
                ],
onSelected: (value) async {
  if (value == 'logout') {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    await chatProvider.handleLogout();  // 使用新的處理登出方法
    await authProvider.logout();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => const LoginScreen(),
        ),
        (route) => false,
      );
    }
  } else if (value == 'clear') {
                    if (context.mounted) {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
                          title: Text(
                            '清除所有對話',
                            style: TextStyle(
                              color: isDarkMode ? Colors.white : Colors.black,
                            ),
                          ),
                          content: Text(
                            '確定要清除所有對話嗎？此操作無法復原。',
                            style: TextStyle(
                              color: isDarkMode ? Colors.white : Colors.black,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(
                                '取消',
                                style: TextStyle(
                                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text(
                                '刪除',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );
                      
                      if (confirm == true) {
                        final conversationProvider = Provider.of<ConversationProvider>(
                          context,
                          listen: false,
                        );
                        await conversationProvider.clearAllConversations();
                        Navigator.pop(context);
                      }
                    }
                  }
                },
              ),
            );
          },
        ),
      ),
    ],
  );
}
}