//lib.screen/login_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/conversation_provider.dart';
import '../config/env.dart';
import 'chat_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late final List<String> _phrases = [
    'Write code.',
    'Search web.',
    'Can see, hear, and speak.',
    'ChatNLM',
  ];
  int _currentPhraseIndex = 0;
  String _currentText = '';
  int _currentCharIndex = 0;
  bool _isTyping = true;
  bool _shouldPause = false;

  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

@override
void initState() {
  super.initState();
  _startTypingAnimation();
  
  _controller = AnimationController(
    duration: const Duration(seconds: 2),
    vsync: this,
  )..repeat(reverse: true);

  _scaleAnimation = Tween<double>(
    begin: 1.0,
    end: 1.05,
  ).animate(CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  ));
}

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _startTypingAnimation() async {
    while (mounted) {
      if (_shouldPause) {
        await Future.delayed(const Duration(milliseconds: 1000));
        _shouldPause = false;
      }

      if (_isTyping) {
        if (_currentCharIndex < _phrases[_currentPhraseIndex].length) {
          setState(() {
            _currentText += _phrases[_currentPhraseIndex][_currentCharIndex];
            _currentCharIndex++;
          });
          await Future.delayed(const Duration(milliseconds: 80));
        } else {
          _isTyping = false;
          _shouldPause = true;
          await Future.delayed(const Duration(milliseconds: 800));
          setState(() {
            _currentText = '';
            _currentCharIndex = 0;
            _currentPhraseIndex = (_currentPhraseIndex + 1) % _phrases.length;
          });
          _isTyping = true;
        }
      }
    }
  }

Future<void> _handleLogin(BuildContext context) async {
  if (_isLoading) return;

  setState(() {
    _isLoading = true;
  });

  try {
    final result = await context.read<AuthProvider>().login();
    if (result && mounted) {
      _navigateToChatScreen(false);  // 非試用模式
    }
  } finally {
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }
}

void _handleTrial(BuildContext context) async {
  final authProvider = context.read<AuthProvider>();
  authProvider.enterTrialMode();
  
  // 使用新的導航方法
  if (mounted) {
    _navigateToChatScreen(true);  // 傳入試用模式標記
  }
}

void _navigateToChatScreen(bool isTrialMode) {
  Navigator.of(context).pushReplacement(
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => const ChatScreen(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 500),
    ),
  );
}

 @override
Widget build(BuildContext context) {
 return Consumer<AuthProvider>(
   builder: (context, authProvider, child) {
     // 如果是試用模式，直接導航到聊天頁面
     if (authProvider.isTrialMode) {
       WidgetsBinding.instance.addPostFrameCallback((_) {
         if (mounted) {
           _navigateToChatScreen(true);
         }
       });
     }

     final isDarkMode = Theme.of(context).brightness == Brightness.dark;
     final size = MediaQuery.of(context).size;

     return Scaffold(
       backgroundColor: isDarkMode ? Colors.black : Colors.white,
       body: Stack(
         fit: StackFit.expand,
         children: [
           // 上方圓形
           Positioned(
             right: -size.width * 0.2,
             top: -size.width * 0.2,
             child: AnimatedBuilder(
               animation: _scaleAnimation,
               builder: (context, child) => Transform.scale(
                 scale: _scaleAnimation.value,
                 child: Container(
                   width: size.width * 0.8,
                   height: size.width * 0.8,
                   decoration: BoxDecoration(
                     shape: BoxShape.circle,
                     gradient: RadialGradient(
                       colors: isDarkMode 
                         ? [Colors.blue.withOpacity(0.4), Colors.blue.withOpacity(0)]
                         : [Colors.blue.withOpacity(0.2), Colors.blue.withOpacity(0)],
                       stops: const [0.2, 0.8],
                     ),
                   ),
                 ),
               ),
             ),
           ),

           // 下方圓形
           Positioned(
             left: -size.width * 0.3,
             bottom: -size.width * 0.3,
             child: AnimatedBuilder(
               animation: _scaleAnimation,
               builder: (context, child) => Transform.scale(
                 scale: _scaleAnimation.value,
                 child: Container(
                   width: size.width * 1.0,
                   height: size.width * 1.0,
                   decoration: BoxDecoration(
                     shape: BoxShape.circle,
                     gradient: RadialGradient(
                       colors: isDarkMode 
                         ? [Colors.purple.withOpacity(0.4), Colors.purple.withOpacity(0)]
                         : [Colors.purple.withOpacity(0.2), Colors.purple.withOpacity(0)],
                       stops: const [0.2, 0.8],
                     ),
                   ),
                 ),
               ),
             ),
           ),

           // 主要內容
           SafeArea(
             child: Column(
               children: [
                 const Spacer(flex: 2),
                 
                 // Logo
                 SvgPicture.asset(
                   isDarkMode
                     ? 'assets/images/logo/Chat-dark.svg'
                     : 'assets/images/logo/Chat-light.svg',
                   height: 80,
                 ),
                 
                 const SizedBox(height: 40),
                 
                 // 流式文字
                 Container(
                   height: 46,
                   alignment: Alignment.center,
                   child: ShaderMask(
                     shaderCallback: (bounds) => LinearGradient(
                       colors: isDarkMode 
                         ? [Colors.blue, Colors.purple]
                         : [Colors.blue.shade700, Colors.purple.shade700],
                     ).createShader(bounds),
                     child: Text(
                       _currentText,
                       style: const TextStyle(
                         fontSize: 26,
                         height: 1.2,
                         fontWeight: FontWeight.w600,
                         color: Colors.white,
                       ),
                     ),
                   ),
                 ),
                 
                 const Spacer(flex: 2),
                 
                 // 按鈕區域
                 Padding(
                   padding: const EdgeInsets.only(bottom: 50),
                   child: Column(
                     children: [
                       // 登入按鈕
                       AnimatedContainer(
                         duration: const Duration(milliseconds: 200),
                         transform: Matrix4.identity()..scale(_isLoading ? 0.95 : 1.0),
                         child: Container(
                           decoration: BoxDecoration(
                             borderRadius: BorderRadius.circular(16),
                             gradient: LinearGradient(
                               colors: isDarkMode 
                                 ? [Colors.blue, Colors.purple]
                                 : [Colors.blue.shade700, Colors.purple.shade700],
                             ),
                             boxShadow: [
                               BoxShadow(
                                 color: Colors.blue.withOpacity(0.3),
                                 blurRadius: 20,
                                 offset: const Offset(0, 10),
                               ),
                             ],
                           ),
                           child: Material(
                             color: Colors.transparent,
                             child: InkWell(
                               borderRadius: BorderRadius.circular(16),
                               onTap: () => _handleLogin(context),
                               child: Container(
                                 padding: const EdgeInsets.symmetric(
                                   horizontal: 30,
                                   vertical: 16,
                                 ),
                                 child: _isLoading
                                   ? const SizedBox(
                                       width: 24,
                                       height: 24,
                                       child: CircularProgressIndicator(
                                         color: Colors.white,
                                         strokeWidth: 2,
                                       ),
                                     )
                                   : const Text(
                                       'Login',
                                       style: TextStyle(
                                         color: Colors.white,
                                         fontSize: 18,
                                         fontWeight: FontWeight.w600,
                                       ),
                                     ),
                               ),
                             ),
                           ),
                         ),
                       ),

                       const SizedBox(height: 16),

                       // 試用按鈕
                       Container(
                         width: 200,
                         decoration: BoxDecoration(
                           borderRadius: BorderRadius.circular(16),
                           border: Border.all(
                             color: isDarkMode ? Colors.grey[400]! : Colors.grey[600]!,
                             width: 1,
                           ),
                         ),
                         child: Material(
                           color: Colors.transparent,
                           child: InkWell(
                             borderRadius: BorderRadius.circular(16),
                             onTap: () => _handleTrial(context),
                             child: Container(
                               padding: const EdgeInsets.symmetric(
                                 horizontal: 20,
                                 vertical: 12,
                               ),
                               child: Text(
                                 'Try without login',
                                 textAlign: TextAlign.center,
                                 style: TextStyle(
                                   color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                   fontSize: 16,
                                   fontWeight: FontWeight.w500,
                                 ),
                               ),
                             ),
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
       ),
     );
   },
 );
}
}