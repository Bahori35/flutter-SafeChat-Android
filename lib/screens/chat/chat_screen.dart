import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../constants/app_colors.dart';
import '../../models/message_model.dart';
import '../../models/user_model.dart';
import '../../models/call_model.dart';
import '../../services/custom_auth_service.dart';
import '../../services/custom_chat_service.dart';
import '../../services/socket_service.dart';
import '../call/call_screen.dart';

class ChatScreen extends StatefulWidget {
  final UserModel currentUser;
  final UserModel peerUser;

  const ChatScreen({
    super.key,
    required this.currentUser,
    required this.peerUser,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final CustomChatService _chatService = CustomChatService();
  final SocketService _socketService = SocketService();
  final ImagePicker _picker = ImagePicker();
  List<MessageModel> _messages = [];
  bool _isLoading = true;
  bool _isUploadingMedia = false;
  late UserModel _peer;

  @override
  void initState() {
    super.initState();
    _peer = widget.peerUser;
    _loadMessages();

    // Mark all existing messages as read when opening chat
    _socketService.emitMessageRead(
      senderId: widget.peerUser.uid,
      receiverId: widget.currentUser.uid,
    );

    // Listen for live messages received from socket
    _socketService.onMessageReceived = (message) {
      if (message.senderId == widget.peerUser.uid) {
        if (mounted) {
          setState(() {
            _messages.insert(0, message.copyWith(isRead: true, isDelivered: true));
          });
          // Immediately send read receipt back since chat is actively open
          _socketService.emitMessageRead(
            senderId: widget.peerUser.uid,
            receiverId: widget.currentUser.uid,
            messageId: message.id,
          );
        }
      }
    };

    // Listen for message delivered receipt (Gray Double Tick)
    _socketService.onMessageDelivered = (data) {
      if (mounted) {
        final messageId = data['messageId']?.toString();
        setState(() {
          _messages = _messages.map((m) {
            if (messageId != null) {
              if (m.id == messageId) {
                return m.copyWith(isDelivered: true);
              }
            } else if (m.senderId == widget.currentUser.uid) {
              return m.copyWith(isDelivered: true);
            }
            return m;
          }).toList();
        });
      }
    };

    // Listen for message read receipt (Blue Double Tick)
    _socketService.onMessageRead = (data) {
      if (mounted) {
        final messageId = data['messageId']?.toString();
        setState(() {
          _messages = _messages.map((m) {
            if (messageId != null) {
              if (m.id == messageId) {
                return m.copyWith(isDelivered: true, isRead: true);
              }
            } else if (m.senderId == widget.currentUser.uid) {
              return m.copyWith(isDelivered: true, isRead: true);
            }
            return m;
          }).toList();
        });
      }
    };

    // Listen for live status change of peer
    _socketService.onUserStatusChange = (userId, isOnline) {
      if (userId == widget.peerUser.uid && mounted) {
        setState(() {
          _peer = _peer.copyWith(isOnline: isOnline);
        });
      }
    };
  }

  void _loadMessages() async {
    final messages = await _chatService.getMessages(widget.currentUser.uid, widget.peerUser.uid);
    if (mounted) {
      setState(() {
        _messages = messages.reversed.toList();
        _isLoading = false;
      });
      // Mark as read
      _socketService.emitMessageRead(
        senderId: widget.peerUser.uid,
        receiverId: widget.currentUser.uid,
      );
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage({String? customContent, MessageType type = MessageType.text, String? mediaUrl}) {
    final text = (customContent ?? _messageController.text).trim();
    if (text.isEmpty && mediaUrl == null) return;

    final newMessage = MessageModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      senderId: widget.currentUser.uid,
      receiverId: widget.peerUser.uid,
      content: text,
      type: type,
      mediaUrl: mediaUrl,
      timestamp: DateTime.now(),
      isRead: false,
    );

    // 1. Emit live via Socket.io to peer & save in MariaDB & trigger single push
    _socketService.sendMessage(
      senderId: widget.currentUser.uid,
      receiverId: widget.peerUser.uid,
      content: text,
      type: type.name,
      mediaUrl: mediaUrl,
    );

    // 2. Add to local list
    setState(() {
      _messages.insert(0, newMessage);
    });

    if (customContent == null) {
      _messageController.clear();
    }
  }

  // Pick Photo or Video from Camera or Gallery
  Future<void> _pickAndSendMedia({required ImageSource source, required bool isVideo}) async {
    try {
      XFile? file;
      if (isVideo) {
        file = await _picker.pickVideo(
          source: source,
          maxDuration: const Duration(minutes: 3),
        );
      } else {
        file = await _picker.pickImage(
          source: source,
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 85,
        );
      }

      if (file == null) return;

      setState(() {
        _isUploadingMedia = true;
      });

      final authService = Provider.of<CustomAuthService>(context, listen: false);
      final mediaUrl = await authService.uploadImage(file.path);

      if (mediaUrl != null && mounted) {
        _sendMessage(
          customContent: isVideo ? '🎥 Video' : '📷 Fotoğraf',
          type: isVideo ? MessageType.video : MessageType.image,
          mediaUrl: mediaUrl,
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Medya yüklenirken bir hata oluştu.'),
            backgroundColor: AppColors.callRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('[MEDIA PICK ERROR] $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingMedia = false;
        });
      }
    }
  }

  // Pick and send Document (PDF, Word, Excel, ZIP, APK, etc.)
  Future<void> _pickAndSendDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty || result.files.single.path == null) {
        return;
      }

      final file = result.files.single;
      final filePath = file.path!;
      final fileName = file.name;

      setState(() {
        _isUploadingMedia = true;
      });

      final authService = Provider.of<CustomAuthService>(context, listen: false);
      final fileUrl = await authService.uploadFile(filePath);

      if (fileUrl != null && mounted) {
        _sendMessage(
          customContent: fileName,
          type: MessageType.doc,
          mediaUrl: fileUrl,
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dosya yüklenirken bir hata oluştu.'),
            backgroundColor: AppColors.callRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('[DOC PICK ERROR] $e');
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingMedia = false;
        });
      }
    }
  }

  // Open / Download external document link
  Future<void> _openDocument(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        await launchUrl(uri, mode: LaunchMode.platformDefault);
      }
    } catch (e) {
      debugPrint('[OPEN DOC ERROR] $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dosya açılamadı veya indirilemedi.'),
            backgroundColor: AppColors.callRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  IconData _getDocumentIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return Icons.picture_as_pdf;
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) return Icons.description;
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx') || lower.endsWith('.csv')) return Icons.table_chart;
    if (lower.endsWith('.zip') || lower.endsWith('.rar') || lower.endsWith('.7z') || lower.endsWith('.tar') || lower.endsWith('.gz')) return Icons.folder_zip;
    if (lower.endsWith('.apk')) return Icons.android;
    if (lower.endsWith('.txt')) return Icons.article;
    if (lower.endsWith('.mp3') || lower.endsWith('.wav') || lower.endsWith('.m4a') || lower.endsWith('.aac')) return Icons.audiotrack;
    return Icons.insert_drive_file;
  }

  Color _getDocumentColor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return const Color(0xFFE53935);
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) return const Color(0xFF1E88E5);
    if (lower.endsWith('.xls') || lower.endsWith('.xlsx') || lower.endsWith('.csv')) return const Color(0xFF43A047);
    if (lower.endsWith('.zip') || lower.endsWith('.rar') || lower.endsWith('.7z')) return const Color(0xFFFB8C00);
    if (lower.endsWith('.apk')) return const Color(0xFF00897B);
    return const Color(0xFF5E35B1);
  }

  void _showMediaPickerSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildMediaOption(
                      icon: Icons.insert_drive_file,
                      label: 'Belge / Dosya',
                      color: const Color(0xFF5F66CD),
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendDocument();
                      },
                    ),
                    _buildMediaOption(
                      icon: Icons.camera_alt,
                      label: 'Fotoğraf Çek',
                      color: Colors.pinkAccent,
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendMedia(source: ImageSource.camera, isVideo: false);
                      },
                    ),
                    _buildMediaOption(
                      icon: Icons.videocam,
                      label: 'Video Çek',
                      color: Colors.deepPurpleAccent,
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendMedia(source: ImageSource.camera, isVideo: true);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildMediaOption(
                      icon: Icons.photo_library,
                      label: 'Galeri Foto',
                      color: Colors.blueAccent,
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendMedia(source: ImageSource.gallery, isVideo: false);
                      },
                    ),
                    _buildMediaOption(
                      icon: Icons.video_library,
                      label: 'Galeri Video',
                      color: Colors.green,
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickAndSendMedia(source: ImageSource.gallery, isVideo: true);
                      },
                    ),
                    const SizedBox(width: 80),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMediaOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: color.withOpacity(0.18),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  void _openFullScreenImage(String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(color: AppColors.primaryLight),
                ),
                errorWidget: (context, url, error) => const Icon(Icons.error, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _startCall(CallType callType) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          currentUser: widget.currentUser,
          peerUser: widget.peerUser,
          callType: callType,
          isCaller: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.chatBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leadingWidth: 32,
        titleSpacing: 0,
        elevation: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 19,
              backgroundImage: CachedNetworkImageProvider(_peer.photoUrl),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _peer.displayName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _peer.isOnline ? 'Çevrimiçi' : 'Çevrimdışı',
                    style: TextStyle(
                      fontSize: 12,
                      color: _peer.isOnline ? AppColors.primaryLight : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam, color: AppColors.textPrimary),
            onPressed: () => _startCall(CallType.video),
          ),
          IconButton(
            icon: const Icon(Icons.call, color: AppColors.textPrimary),
            onPressed: () => _startCall(CallType.audio),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: AppColors.textPrimary),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Uploading banner
          if (_isUploadingMedia)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              color: AppColors.primaryLight.withOpacity(0.2),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryLight),
                  ),
                  SizedBox(width: 10),
                  Text('Medya yükleniyor...', style: TextStyle(color: AppColors.primaryLight, fontSize: 13)),
                ],
              ),
            ),

          // Message List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primaryLight))
                : _messages.isEmpty
                    ? const Center(
                        child: Text(
                          'Sohbete başlayın 👋',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        reverse: true,
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final isMe = message.senderId == widget.currentUser.uid;
                          return _buildMessageBubble(message, isMe);
                        },
                      ),
          ),

          // Message Input Field
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildDocumentWidget(MessageModel message) {
    final fileName = message.content.isNotEmpty ? message.content : 'Belge / Doküman';
    final docIcon = _getDocumentIcon(fileName);
    final docColor = _getDocumentColor(fileName);
    final ext = fileName.contains('.') ? fileName.split('.').last.toUpperCase() : 'DOC';

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        if (message.mediaUrl != null && message.mediaUrl!.isNotEmpty) {
          _openDocument(message.mediaUrl!);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: docColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(docIcon, color: docColor, size: 24),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$ext • İndir / Aç',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 15,
              backgroundColor: AppColors.primaryLight.withOpacity(0.2),
              child: const Icon(
                Icons.arrow_downward,
                color: AppColors.primaryLight,
                size: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(MessageModel message, bool isMe) {
    final bool isDoc = message.type == MessageType.doc;
    final bool hasMedia = message.mediaUrl != null && message.mediaUrl!.isNotEmpty;
    final bool isImage = message.type == MessageType.image || (hasMedia && !isDoc && !message.mediaUrl!.endsWith('.mp4'));

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: EdgeInsets.all(hasMedia && !isDoc ? 4 : 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isMe ? AppColors.myMessageBubble : AppColors.peerMessageBubble,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isMe ? 14 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (isDoc) ...[
              _buildDocumentWidget(message),
            ] else if (hasMedia) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: isImage
                    ? GestureDetector(
                        onTap: () => _openFullScreenImage(message.mediaUrl!),
                        child: CachedNetworkImage(
                          imageUrl: message.mediaUrl!,
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            height: 200,
                            color: Colors.black12,
                            child: const Center(child: CircularProgressIndicator(color: AppColors.primaryLight, strokeWidth: 2)),
                          ),
                          errorWidget: (context, url, error) => Container(
                            height: 200,
                            color: Colors.black12,
                            child: const Icon(Icons.broken_image, color: Colors.white54, size: 40),
                          ),
                        ),
                      )
                    : Container(
                        height: 180,
                        color: Colors.black26,
                        child: const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: AppColors.primaryLight,
                                child: Icon(Icons.play_arrow, color: Colors.white, size: 36),
                              ),
                              SizedBox(height: 8),
                              Text('Video Mesajı', style: TextStyle(color: Colors.white, fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
              ),
              if (message.content.isNotEmpty && message.content != '📷 Fotoğraf' && message.content != '🎥 Video')
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
                  child: Text(
                    message.content,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
                  ),
                ),
            ] else ...[
              Text(
                message.content,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  height: 1.3,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: hasMedia ? 4 : 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat('HH:mm').format(message.timestamp),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      (message.isRead || message.isDelivered) ? Icons.done_all : Icons.done,
                      size: 15,
                      color: message.isRead ? AppColors.accent : AppColors.textSecondary,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: AppColors.surface,
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file, color: AppColors.textSecondary),
              onPressed: _showMediaPickerSheet,
            ),
            IconButton(
              icon: const Icon(Icons.camera_alt, color: AppColors.primaryLight),
              onPressed: () => _pickAndSendMedia(source: ImageSource.camera, isVideo: false),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _messageController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'Mesaj yazın...',
                    hintStyle: TextStyle(color: AppColors.textSecondary),
                    border: InputBorder.none,
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 6),
            CircleAvatar(
              radius: 23,
              backgroundColor: AppColors.primaryLight,
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: () => _sendMessage(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
