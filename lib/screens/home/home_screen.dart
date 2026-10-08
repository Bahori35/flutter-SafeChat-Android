import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../../constants/app_colors.dart';
import '../../models/user_model.dart';
import '../../models/call_model.dart';
import '../../models/story_model.dart';
import '../../services/custom_auth_service.dart';
import '../../services/custom_chat_service.dart';
import '../../services/socket_service.dart';
import '../../services/notification_service.dart';
import '../chat/chat_screen.dart';
import '../call/call_screen.dart';
import '../profile/profile_screen.dart';
import '../story/story_view_screen.dart';
import '../story/add_story_screen.dart';

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

  // Phone Contacts Match
  List<UserModel> _phoneContacts = [];
  bool _isSyncingContacts = false;
  bool _hasContactPermission = false;

  // Story state
  List<UserStoryGroup> _storyGroups = [];
  bool _isLoadingStories = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
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
        _loadStories();

        // Check if there is an incoming call waiting for us (e.g. app was launched from notification)
        _checkPendingIncomingCall(currentUser);
      }
    });
  }

  void _loadStories() async {
    final authService = Provider.of<CustomAuthService>(context, listen: false);
    final currentUser = authService.currentUser;
    if (currentUser != null) {
      final stories = await _chatService.getStories(currentUser.uid);
      if (mounted) {
        setState(() {
          _storyGroups = stories;
          _isLoadingStories = false;
        });
      }
    }
  }

  void _checkPendingIncomingCall(UserModel currentUser) async {
    try {
      final response = await http.get(
        Uri.parse('${CustomAuthService.baseUrl.replaceAll('/api', '')}/api/calls/pending/${currentUser.uid}'),
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['hasPendingCall'] == true && data['callData'] != null) {
          debugPrint('[CALL] Bekleyen gelen arama bulundu, dialog aciliyor!');
          _notificationService.startRingtone();
          _showIncomingCallDialog(Map<String, dynamic>.from(data['callData']), currentUser);
        }
      }
    } catch (e) {
      debugPrint('[CALL] Pending call check error: $e');
    }
  }

  void _initFirebaseMessaging(CustomAuthService authService) async {
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;

      // Request notification permissions
      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint('[FCM] Bildirim izin durumu: ${settings.authorizationStatus}');

      String? token = await messaging.getToken();
      if (token != null) {
        debugPrint('[FCM] Cihaz Token alindi: $token');
        await authService.syncFcmToken(token);
      }

      messaging.onTokenRefresh.listen((newToken) {
        debugPrint('[FCM] Token yenilendi: $newToken');
        authService.syncFcmToken(newToken);
      });
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
      _syncDeviceContacts(silent: true);
    }
  }

  Future<void> _syncDeviceContacts({bool silent = false}) async {
    final authService = Provider.of<CustomAuthService>(context, listen: false);
    final currentUser = authService.currentUser;
    if (currentUser == null) return;

    if (!silent) {
      setState(() {
        _isSyncingContacts = true;
      });
    }

    try {
      bool permission = await FlutterContacts.requestPermission(readonly: true);
      if (mounted) {
        setState(() {
          _hasContactPermission = permission;
        });
      }

      if (permission) {
        List<Contact> contacts = await FlutterContacts.getContacts(withProperties: true, withPhoto: false);
        List<String> rawNumbers = [];
        for (var contact in contacts) {
          for (var phone in contact.phones) {
            if (phone.number.isNotEmpty) {
              rawNumbers.add(phone.number);
            }
          }
        }

        final myUid = int.tryParse(currentUser.uid) ?? 0;
        final matched = await _chatService.syncContacts(
          userId: myUid,
          phoneNumbers: rawNumbers,
        );

        if (mounted) {
          setState(() {
            _phoneContacts = matched;
            _isSyncingContacts = false;
          });
          if (!silent) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${matched.length} rehber kişisi uygulamada bulundu!'),
                backgroundColor: AppColors.primaryLight,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      } else {
        if (mounted) {
          setState(() {
            _isSyncingContacts = false;
          });
          if (!silent) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Rehber izni verilmedi. Ayarlardan izin verebilirsiniz.'),
                backgroundColor: AppColors.callRed,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[CONTACTS] Sync error: $e');
      if (mounted) {
        setState(() {
          _isSyncingContacts = false;
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
              if (val == 'profile') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              } else if (val == 'logout') {
                authService.signOut();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundImage: CachedNetworkImageProvider(currentUser.photoUrl),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          currentUser.displayName,
                          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          'Profili Düzenle',
                          style: const TextStyle(color: AppColors.primaryLight, fontSize: 11),
                        ),
                      ],
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
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          tabs: const [
            Tab(text: 'SOHBETLER'),
            Tab(text: 'DURUM'),
            Tab(text: 'KİŞİLER'),
            Tab(text: 'ARAMALAR'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildChatsTab(currentUser),
          _buildStoriesTab(currentUser),
          _buildUsersTab(currentUser),
          _buildCallsTab(currentUser),
        ],
      ),
      floatingActionButton: _buildFab(currentUser),
    );
  }

  Widget? _buildFab(UserModel currentUser) {
    if (_tabController.index == 0) {
      return FloatingActionButton(
        backgroundColor: AppColors.primaryLight,
        onPressed: () {
          _tabController.animateTo(2); // Go to contacts
        },
        child: const Icon(Icons.message, color: Colors.white),
      );
    } else if (_tabController.index == 1) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            backgroundColor: AppColors.surfaceLight,
            onPressed: () => _navigateToAddStory(currentUser),
            child: const Icon(Icons.edit, color: Colors.white),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            backgroundColor: AppColors.primaryLight,
            onPressed: () => _navigateToAddStory(currentUser),
            child: const Icon(Icons.camera_alt, color: Colors.white),
          ),
        ],
      );
    }
    return null;
  }

  void _navigateToAddStory(UserModel currentUser) async {
    final res = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddStoryScreen(currentUser: currentUser),
      ),
    );
    if (res == true) {
      _loadStories();
    }
  }

  void _openStoryViewer(int groupIndex, UserModel currentUser) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StoryViewScreen(
          storyGroups: _storyGroups,
          initialGroupIndex: groupIndex,
          currentUser: currentUser,
          onStoryDeletedOrUpdated: _loadStories,
        ),
      ),
    ).then((_) {
      _loadStories();
    });
  }

  // Stories (Durum) Tab
  Widget _buildStoriesTab(UserModel currentUser) {
    if (_isLoadingStories) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryLight));
    }

    final myUid = currentUser.uid;
    UserStoryGroup? myStoryGroup;
    List<UserStoryGroup> recentUpdates = [];
    List<UserStoryGroup> viewedUpdates = [];

    for (final group in _storyGroups) {
      if (group.userId.toString() == myUid) {
        myStoryGroup = group;
      } else {
        if (group.allViewed) {
          viewedUpdates.add(group);
        } else {
          recentUpdates.add(group);
        }
      }
    }

    return RefreshIndicator(
      color: AppColors.primaryLight,
      onRefresh: () async {
        _loadStories();
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // My Status Tile
          ListTile(
            onTap: () {
              if (myStoryGroup != null && myStoryGroup.stories.isNotEmpty) {
                final myIdx = _storyGroups.indexWhere((g) => g.userId.toString() == myUid);
                _openStoryViewer(myIdx != -1 ? myIdx : 0, currentUser);
              } else {
                _navigateToAddStory(currentUser);
              }
            },
            leading: Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: (myStoryGroup != null && myStoryGroup.stories.isNotEmpty)
                        ? Border.all(color: AppColors.primaryLight, width: 2.5)
                        : null,
                  ),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.surfaceLight,
                    backgroundImage: currentUser.photoUrl.isNotEmpty
                        ? CachedNetworkImageProvider(currentUser.photoUrl)
                        : null,
                    child: currentUser.photoUrl.isEmpty
                        ? const Icon(Icons.person, color: AppColors.textSecondary)
                        : null,
                  ),
                ),
                if (myStoryGroup == null || myStoryGroup.stories.isEmpty)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: AppColors.primaryLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add, color: Colors.white, size: 16),
                    ),
                  ),
              ],
            ),
            title: const Text('Durumum', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
            subtitle: Text(
              (myStoryGroup != null && myStoryGroup.stories.isNotEmpty)
                  ? '${myStoryGroup.stories.length} hikaye • Görmek için dokunun'
                  : 'Durum güncellemesi eklemek için dokunun',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.camera_alt, color: AppColors.primaryLight),
              onPressed: () => _navigateToAddStory(currentUser),
            ),
          ),

          if (recentUpdates.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Son Güncellemeler',
                style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            ...recentUpdates.map((group) {
              final idx = _storyGroups.indexOf(group);
              return ListTile(
                onTap: () => _openStoryViewer(idx, currentUser),
                leading: Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primaryLight, width: 2.5),
                  ),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.surfaceLight,
                    backgroundImage: group.userPhotoUrl.isNotEmpty
                        ? CachedNetworkImageProvider(group.userPhotoUrl)
                        : null,
                    child: group.userPhotoUrl.isEmpty
                        ? const Icon(Icons.person, color: AppColors.textSecondary)
                        : null,
                  ),
                ),
                title: Text(group.displayName, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                subtitle: Text(
                  '${group.stories.length} yeni güncelleme',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
              );
            }),
          ],

          if (viewedUpdates.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Görülen Güncellemeler',
                style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            ...viewedUpdates.map((group) {
              final idx = _storyGroups.indexOf(group);
              return ListTile(
                onTap: () => _openStoryViewer(idx, currentUser),
                leading: Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surfaceLight, width: 2.5),
                  ),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.surfaceLight,
                    backgroundImage: group.userPhotoUrl.isNotEmpty
                        ? CachedNetworkImageProvider(group.userPhotoUrl)
                        : null,
                    child: group.userPhotoUrl.isEmpty
                        ? const Icon(Icons.person, color: AppColors.textSecondary)
                        : null,
                  ),
                ),
                title: Text(group.displayName, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                subtitle: const Text('Görüldü', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              );
            }),
          ],

          if (recentUpdates.isEmpty && viewedUpdates.isEmpty && (myStoryGroup == null || myStoryGroup.stories.isEmpty)) ...[
            const SizedBox(height: 60),
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    Icon(Icons.history_toggle_off_rounded, size: 64, color: AppColors.textMuted),
                    SizedBox(height: 12),
                    Text(
                      'Henüz hiçbir durum paylaşılmadı.',
                      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Yukarıdaki butona veya kameraya basarak ilk durumunuzu paylaşın!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
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

    return Column(
      children: [
        // Top Horizontal Story Avatar Bar (Instagram / Modern WhatsApp Style)
        if (_storyGroups.isNotEmpty || true)
          Container(
            height: 96,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.surface, width: 1)),
            ),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                // My Story Bubble
                GestureDetector(
                  onTap: () {
                    final myUid = currentUser.uid;
                    final myIdx = _storyGroups.indexWhere((g) => g.userId.toString() == myUid);
                    if (myIdx != -1) {
                      _openStoryViewer(myIdx, currentUser);
                    } else {
                      _navigateToAddStory(currentUser);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(2.5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: _storyGroups.any((g) => g.userId.toString() == currentUser.uid)
                                    ? Border.all(color: AppColors.primaryLight, width: 2.5)
                                    : null,
                              ),
                              child: CircleAvatar(
                                radius: 25,
                                backgroundColor: AppColors.surfaceLight,
                                backgroundImage: currentUser.photoUrl.isNotEmpty
                                    ? CachedNetworkImageProvider(currentUser.photoUrl)
                                    : null,
                                child: currentUser.photoUrl.isEmpty
                                    ? const Icon(Icons.person, color: AppColors.textSecondary)
                                    : null,
                              ),
                            ),
                            if (!_storyGroups.any((g) => g.userId.toString() == currentUser.uid))
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: const BoxDecoration(
                                    color: AppColors.primaryLight,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.add, color: Colors.white, size: 14),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Hikayen',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),

                // Other Users Stories
                ..._storyGroups.where((g) => g.userId.toString() != currentUser.uid).map((group) {
                  final groupIdx = _storyGroups.indexOf(group);
                  return GestureDetector(
                    onTap: () => _openStoryViewer(groupIdx, currentUser),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(2.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: group.allViewed ? AppColors.surfaceLight : AppColors.primaryLight,
                                width: 2.5,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 25,
                              backgroundColor: AppColors.surfaceLight,
                              backgroundImage: group.userPhotoUrl.isNotEmpty
                                  ? CachedNetworkImageProvider(group.userPhotoUrl)
                                  : null,
                              child: group.userPhotoUrl.isEmpty
                                  ? const Icon(Icons.person, color: AppColors.textSecondary)
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: 62,
                            child: Text(
                              group.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),

        // Chat List
        Expanded(
          child: filteredUsers.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Text(
                      'Henüz sohbet bulunmuyor.\nKişiler sekmesinden birini seçip konuşmaya başlayın!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary, height: 1.5, fontSize: 15),
                    ),
                  ),
                )
              : ListView.separated(
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
                ),
        ),
      ],
    );
  }

  // Users / Contacts Tab
  Widget _buildUsersTab(UserModel currentUser) {
    if (_isLoadingUsers) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryLight));
    }

    var filteredUsers = _users;
    var filteredPhoneContacts = _phoneContacts;

    if (_searchQuery.isNotEmpty) {
      filteredUsers = filteredUsers
          .where((u) =>
              u.displayName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              u.username.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              u.phoneNumber.contains(_searchQuery))
          .toList();

      filteredPhoneContacts = filteredPhoneContacts
          .where((u) =>
              u.displayName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              u.username.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              u.phoneNumber.contains(_searchQuery))
          .toList();
    }

    return RefreshIndicator(
      color: AppColors.primaryLight,
      onRefresh: () async {
        _loadUsers();
      },
      child: ListView(
        children: [
          // Header: Sync Contacts Action Tile
          ListTile(
            onTap: _isSyncingContacts ? null : () => _syncDeviceContacts(silent: false),
            leading: CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.surfaceLight,
              child: _isSyncingContacts
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: AppColors.primaryLight, strokeWidth: 2),
                    )
                  : const Icon(Icons.contacts, color: AppColors.primaryLight),
            ),
            title: const Text('Rehberi Yenile / Eşitle', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
            subtitle: Text(
              _phoneContacts.isNotEmpty
                  ? 'Rehberinizden ${_phoneContacts.length} kişi bu uygulamayı kullanıyor'
                  : 'Rehberinizdeki kişileri otomatik eşleştirin',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            trailing: const Icon(Icons.sync, color: AppColors.primaryLight),
          ),
          const Divider(color: AppColors.surface),

          // Section 1: Phone Contacts using the app
          if (filteredPhoneContacts.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Text(
                'Rehberinizdeki Kullanıcılar',
                style: TextStyle(color: AppColors.primaryLight, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            ...filteredPhoneContacts.map((user) {
              return ListTile(
                leading: Stack(
                  children: [
                    CircleAvatar(
                      radius: 24,
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
                title: Text(user.displayName, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                subtitle: Text(
                  '${user.phoneNumber.isNotEmpty ? user.phoneNumber : "@${user.username}"} • ${user.isOnline ? "Çevrimiçi" : "Çevrimdışı"}',
                  style: TextStyle(
                    color: user.isOnline ? AppColors.primaryLight : AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.call, color: AppColors.primaryLight, size: 22),
                      onPressed: () => _startAudioOrVideoCall(user, CallType.audio),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chat, color: AppColors.primaryLight, size: 22),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(peerUser: user, currentUser: currentUser),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            }),
            const Divider(color: AppColors.surface),
          ],

          // Section 2: All registered application users
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              'Tüm Kayıtlı Kullanıcılar',
              style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          if (filteredUsers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(
                child: Text('Kullanıcı bulunamadı', style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            ...filteredUsers.map((user) {
              return ListTile(
                leading: Stack(
                  children: [
                    CircleAvatar(
                      radius: 24,
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
                title: Text(user.displayName, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
                subtitle: Text(
                  '@${user.username} ${user.phoneNumber.isNotEmpty ? "• ${user.phoneNumber}" : ""} • ${user.isOnline ? "Çevrimiçi" : "Çevrimdışı"}',
                  style: TextStyle(
                    color: user.isOnline ? AppColors.primaryLight : AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.call, color: AppColors.primaryLight, size: 22),
                      onPressed: () => _startAudioOrVideoCall(user, CallType.audio),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chat, color: AppColors.primaryLight, size: 22),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(peerUser: user, currentUser: currentUser),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
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
