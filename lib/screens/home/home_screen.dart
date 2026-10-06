import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../constants/app_colors.dart';
import '../../models/user_model.dart';
import '../../models/call_model.dart';
import '../../services/custom_auth_service.dart';
import '../../services/custom_chat_service.dart';
import '../../services/socket_service.dart';
import '../../services/notification_service.dart';
import '../chat/chat_screen.dart';
import '../call/call_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final CustomChatService _chatService = CustomChatService();
  final SocketService _socketService = SocketService();
  final NotificationService _notificationService = NotificationService();
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String _searchQuery = '';
  List<UserModel> _users = [];
  bool _isLoadingUsers = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _notificationService.init();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authService = Provider.of<CustomAuthService>(context, listen: false);
      final currentUser = authService.currentUser;
      if (currentUser != null) {
        // Connect Socket.io client
        _socketService.initSocket(currentUser.uid);

        // Register FCM Push Notifications
        _initFirebaseMessaging(authService);

        // Listen for live messages received while in HomeScreen
        _socketService.onMessageReceived = (message) {
          String senderDisplayName = message.senderName ?? 'Yeni Mesaj';
          try {
            final senderObj = _users.firstWhere((u) => u.uid == message.senderId);
            senderDisplayName = senderObj.displayName;
          } catch (_) {}

          _notificationService.showMessageNotification(
            id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            senderName: senderDisplayName,
            messageContent: message.content,
          );
        };

        // Listen for incoming calls
        _socketService.onIncomingCall = (callData) {
          _notificationService.startRingtone();
          _showIncomingCallDialog(callData, currentUser);
        };

        // Listen for real-time user online/offline status changes
        _socketService.onUserStatusChange = (userId, isOnline) {
          if (mounted) {
            setState(() {
              final index = _users.indexWhere((u) => u.uid == userId);
              if (index != -1) {
                _users[index] = _users[index].copyWith(isOnline: isOnline);
              }
            });
          }
        };

        _loadUsers();
      }
    });
  }

  void _initFirebaseMessaging(CustomAuthService authService) async {
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;

      // Request notification permissions
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        String? token = await messaging.getToken();
        if (token != null) {
          authService.syncFcmToken(token);
        }

        messaging.onTokenRefresh.listen((newToken) {
          authService.syncFcmToken(newToken);
        });
      }
    } catch (e) {
      debugPrint('[FCM] Error initializing messaging: $e');
    }
  }




  void _showIncomingCallDialog(Map<String, dynamic> callData, UserModel currentUser) {
    final callerData = callData['caller'] as Map<String, dynamic>;
    final callTypeStr = callData['callType'] ?? 'video';
    final offer = Map<String, dynamic>.from(callData['offer']);

    final callerUser = UserModel(
      uid: callerData['uid'].toString(),
      username: callerData['username'] ?? 'User',
      email: '',
      displayName: callerData['displayName'] ?? callerData['username'] ?? 'User',
      photoUrl: callerData['photoUrl'] ?? '',
    );

    final int callNotificationId = 9999;
    _notificationService.showIncomingCallNotification(
      id: callNotificationId,
      callerName: callerUser.displayName,
      callType: callTypeStr == 'video' ? 'Görüntülü' : 'Sesli',
    );

    bool isDialogClosed = false;
    BuildContext? dialogContext;

    // If caller cancels before we answer, dismiss the dialog immediately!
    _socketService.onCallEnded = () {
      if (!isDialogClosed) {
        isDialogClosed = true;
        _notificationService.cancelCallNotification(callNotificationId);
        _notificationService.stopRingtone();
        if (dialogContext != null && Navigator.canPop(dialogContext!)) {
          Navigator.pop(dialogContext!);
        }
      }
    };

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return Dialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundImage: CachedNetworkImageProvider(callerUser.photoUrl),
                ),
                const SizedBox(height: 16),
                Text(
                  callerUser.displayName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  callTypeStr == 'video' ? 'Gelen Görüntülü Arama...' : 'Gelen Sesli Arama...',
                  style: const TextStyle(color: AppColors.primaryLight, fontSize: 14),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.call_end, color: AppColors.callRed, size: 36),
                      onPressed: () {
                        isDialogClosed = true;
                        _notificationService.cancelCallNotification(callNotificationId);
                        _notificationService.stopRingtone();
                        _socketService.emitEndCall(callerUser.uid);
                        Navigator.pop(ctx);
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        callTypeStr == 'video' ? Icons.videocam : Icons.call,
                        color: AppColors.callGreen,
                        size: 36,
                      ),
                      onPressed: () {
                        isDialogClosed = true;
                        _notificationService.cancelCallNotification(callNotificationId);
                        _notificationService.stopRingtone();
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CallScreen(
                              currentUser: currentUser,
                              peerUser: callerUser,
                              callType: callTypeStr == 'video' ? CallType.video : CallType.audio,
                              isCaller: false,
                              incomingOffer: offer,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );


  }

  void _loadUsers() async {
    final authService = Provider.of<CustomAuthService>(context, listen: false);
    final currentUser = authService.currentUser;
    if (currentUser != null) {
      final users = await _chatService.getUsers(currentUser.uid);
      if (mounted) {
        setState(() {
          _users = users;
          _isLoadingUsers = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _startAudioOrVideoCall(UserModel peerUser, CallType callType) {
    final authService = Provider.of<CustomAuthService>(context, listen: false);
    final currentUser = authService.currentUser;
    if (currentUser == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          currentUser: currentUser,
          peerUser: peerUser,
          callType: callType,
          isCaller: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<CustomAuthService>(context);
    final currentUser = authService.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primaryLight),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Kullanıcı adı veya isim ara...',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val.trim();
                  });
                },
              )
            : const Text(
                'WhatsApp',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close : Icons.search,
              color: AppColors.textSecondary,
            ),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                _searchQuery = '';
                _searchController.clear();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
            onPressed: () {
              setState(() {
                _isLoadingUsers = true;
              });
              _loadUsers();
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
            color: AppColors.surfaceLight,
            onSelected: (val) {
              if (val == 'logout') {
                authService.signOut();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    const Icon(Icons.person, color: AppColors.textPrimary, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      '@${currentUser.username}',
                      style: const TextStyle(color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: AppColors.callRed, size: 20),
                    SizedBox(width: 10),
                    Text(
                      'Çıkış Yap',
                      style: TextStyle(color: AppColors.callRed),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primaryLight,
          indicatorWeight: 3.5,
          labelColor: AppColors.primaryLight,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          tabs: const [
            Tab(text: 'SOHBETLER'),
            Tab(text: 'KİŞİLER'),
            Tab(text: 'ARAMALAR'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChatsTab(currentUser),
          _buildUsersTab(currentUser),
          _buildCallsTab(currentUser),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primaryLight,
        onPressed: () {
          _tabController.animateTo(1);
        },
        child: const Icon(Icons.message, color: Colors.white),
      ),
    );
  }

  // Chats Tab
  Widget _buildChatsTab(UserModel currentUser) {
    if (_isLoadingUsers) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryLight));
    }

    var filteredUsers = _users;
    if (_searchQuery.isNotEmpty) {
      filteredUsers = filteredUsers
          .where((u) =>
              u.displayName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              u.username.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    if (filteredUsers.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'Henüz sohbet bulunmuyor.\nKişiler sekmesinden birini seçip konuşmaya başlayın!',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, height: 1.5, fontSize: 15),
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: filteredUsers.length,
      separatorBuilder: (ctx, i) => const Divider(color: AppColors.surface, height: 1, indent: 76),
      itemBuilder: (context, index) {
        final user = filteredUsers[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Stack(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.surfaceLight,
                backgroundImage: CachedNetworkImageProvider(user.photoUrl),
              ),
              if (user.isOnline)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.background, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          title: Text(
            user.displayName,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          subtitle: Text(
            user.status,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.call, color: AppColors.primaryLight, size: 22),
                onPressed: () => _startAudioOrVideoCall(user, CallType.audio),
              ),
              IconButton(
                icon: const Icon(Icons.videocam, color: AppColors.primaryLight, size: 24),
                onPressed: () => _startAudioOrVideoCall(user, CallType.video),
              ),
            ],
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(peerUser: user, currentUser: currentUser),
              ),
            );
          },
        );
      },
    );
  }

  // Users Tab
  Widget _buildUsersTab(UserModel currentUser) {
    if (_isLoadingUsers) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryLight));
    }

    var filteredUsers = _users;
    if (_searchQuery.isNotEmpty) {
      filteredUsers = filteredUsers
          .where((u) =>
              u.displayName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              u.username.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }

    return ListView.builder(
      itemCount: filteredUsers.length,
      itemBuilder: (context, index) {
        final user = filteredUsers[index];
        return ListTile(
          leading: CircleAvatar(
            radius: 24,
            backgroundImage: CachedNetworkImageProvider(user.photoUrl),
          ),
          title: Text(user.displayName, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          subtitle: Text('@${user.username} • ${user.isOnline ? "Çevrimiçi" : "Çevrimdışı"}',
              style: TextStyle(
                color: user.isOnline ? AppColors.primaryLight : AppColors.textSecondary,
                fontSize: 13,
              )),
          trailing: IconButton(
            icon: const Icon(Icons.chat, color: AppColors.primaryLight),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(peerUser: user, currentUser: currentUser),
                ),
              );
            },
          ),
        );
      },
    );
  }

  // Calls Tab
  Widget _buildCallsTab(UserModel currentUser) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.video_call_rounded, size: 70, color: AppColors.textMuted),
            const SizedBox(height: 16),
            const Text(
              'Arkadaşlarınla sesli veya görüntülü konuş!',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Herhangi bir kişinin yanındaki arama butonuna basarak\nanında HD WebRTC görüşmesi başlatabilirsiniz.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
