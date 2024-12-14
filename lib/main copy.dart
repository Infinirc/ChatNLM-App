// main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
import 'providers/chat_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/conversation_provider.dart';
import 'managers/message_rating_manager.dart';
import 'config/env.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthProvider(),
        ),
        ChangeNotifierProxyProvider<AuthProvider, MessageRatingManager>(
          create: (context) => MessageRatingManager(
            baseUrl: Env.conversationApiUrl,
            isTrialMode: context.read<AuthProvider>().isTrialMode,
          ),
          update: (context, auth, previous) {
            if (previous != null && auth.isTrialMode == previous.isTrialMode) {
              return previous;
            }
            return MessageRatingManager(
              baseUrl: Env.conversationApiUrl,
              isTrialMode: auth.isTrialMode,
            );
          },
        ),
        ChangeNotifierProxyProvider<AuthProvider, ConversationProvider>(
          create: (context) => ConversationProvider(
            baseUrl: Env.conversationApiUrl,
            userId: context.read<AuthProvider>().userId ?? '',
            isTrialMode: context.read<AuthProvider>().isTrialMode,
          ),
          update: (context, auth, previous) {
            if (previous != null && previous.userId == auth.userId) {
              return previous;
            }
            return ConversationProvider(
              baseUrl: Env.conversationApiUrl,
              userId: auth.userId ?? '',
              isTrialMode: auth.isTrialMode,
            );
          },
        ),
        ChangeNotifierProxyProvider2<AuthProvider, ConversationProvider, ChatProvider>(
          create: (context) => ChatProvider(
            context,
            baseUrl: Env.llmApiUrl,
            conversationUrl: Env.conversationApiUrl,
            isTrialMode: context.read<AuthProvider>().isTrialMode,
          ),
          update: (context, auth, conversation, previous) {
            if (previous == null) {
              return ChatProvider(
                context,
                baseUrl: Env.llmApiUrl,
                conversationUrl: Env.conversationApiUrl,
                isTrialMode: auth.isTrialMode,
              );
            }
            return previous;
          },
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChatNLM',
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFF7F7F7),
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFFF7F7F7),
          elevation: 1,
          shadowColor: Colors.black.withOpacity(0.1),
          iconTheme: const IconThemeData(color: Color(0xFF2C2C2E)),
          titleTextStyle: const TextStyle(
            color: Color(0xFF2C2C2E),
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        cardTheme: CardTheme(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Colors.grey.withOpacity(0.1),
              width: 1,
            ),
          ),
        ),
        primaryColor: const Color(0xFF007AFF),
        inputDecorationTheme: InputDecorationTheme(
          fillColor: Colors.white,
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
        ),
        iconTheme: const IconThemeData(
          color: Color(0xFF2C2C2E),
          size: 24,
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        cardTheme: CardTheme(
          color: const Color(0xFF1C1C1E),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          fillColor: const Color(0xFF1C1C1E),
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
        ),
        iconTheme: const IconThemeData(
          color: Colors.white,
          size: 24,
        ),
      ),
      themeMode: ThemeMode.system,
      home: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          if (!auth.isAuthenticated) {
            return const LoginScreen();
          }
          return const ChatScreen();
        },
      ),
    );
  }
}