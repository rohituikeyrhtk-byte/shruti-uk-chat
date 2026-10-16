#!/data/data/com.termux/files/usr/bin/bash
echo "🚀 Setting up SHRUTI U.K. CHAT..."

# 1. Update pubspec.yaml
cat > pubspec.yaml << 'EOF'
name: shruti_uk_chat
description: SHRUTI U.K. CHAT - Dil se baat, hamesha saath
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.0.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  firebase_core: ^3.6.0
  firebase_auth: ^5.3.1
  cloud_firestore: ^5.4.4
  image_picker: ^1.1.2
  file_picker: ^8.1.2
  cached_network_image: ^3.4.1
  intl: ^0.19.0
  http: ^1.2.2
  url_launcher: ^6.3.1
  video_player: ^2.9.2
  cupertino_icons: ^1.0.8

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
EOF

echo "✅ pubspec.yaml updated"

# 2. Create chat_page.dart
cat > lib/chat_page.dart << 'EOF'
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'config.dart';

class ChatPage extends StatefulWidget {
  final String receiverId;
  final String receiverEmail;
  const ChatPage({super.key, required this.receiverId, required this.receiverEmail});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final msgCtrl = TextEditingController();
  final me = FirebaseAuth.instance.currentUser!;
  bool uploading = false;

  String get chatId {
    final ids = [me.uid, widget.receiverId]..sort();
    return ids.join('_');
  }

  Future<String?> uploadToTelegram(File file, String type) async {
    try {
      String endpoint;
      String fileField;
      if (type == 'image') {
        endpoint = 'sendPhoto';
        fileField = 'photo';
      } else if (type == 'video') {
        endpoint = 'sendVideo';
        fileField = 'video';
      } else {
        endpoint = 'sendDocument';
        fileField = 'document';
      }

      final uri = Uri.parse('https://api.telegram.org/bot$TG_TOKEN/$endpoint');
      final request = http.MultipartRequest('POST', uri);
      request.fields['chat_id'] = TG_CHAT_ID;
      request.files.add(await http.MultipartFile.fromPath(fileField, file.path));

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode != 200) {
        debugPrint('TG upload failed: ${response.body}');
        return null;
      }

      final data = jsonDecode(response.body);
      if (data['ok'] != true) return null;

      String? fileId;
      final result = data['result'];
      if (type == 'image' && result['photo'] != null) {
        final photos = result['photo'] as List;
        fileId = photos.last['file_id'];
      } else if (type == 'video' && result['video'] != null) {
        fileId = result['video']['file_id'];
      } else if (result['document'] != null) {
        fileId = result['document']['file_id'];
      }

      if (fileId == null) return null;

      final getFileUri = Uri.parse(
          'https://api.telegram.org/bot$TG_TOKEN/getFile?file_id=$fileId');
      final fileResp = await http.get(getFileUri);
      final fileData = jsonDecode(fileResp.body);
      if (fileData['ok'] != true) return null;

      final filePath = fileData['result']['file_path'];
      return 'https://api.telegram.org/file/bot$TG_TOKEN/$filePath';
    } catch (e) {
      debugPrint('TG error: $e');
      return null;
    }
  }

  Future<void> sendMessage({
    String? text,
    String? fileUrl,
    String? type,
    String? fileName,
  }) async {
    if ((text == null || text.trim().isEmpty) && fileUrl == null) return;
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add({
      'senderId': me.uid,
      'receiverId': widget.receiverId,
      'text': text ?? '',
      'fileUrl': fileUrl ?? '',
      'type': type ?? 'text',
      'fileName': fileName ?? '',
      'time': FieldValue.serverTimestamp(),
    });
    msgCtrl.clear();
  }

  Future<void> uploadAndSend(File file, String name, String type) async {
    setState(() => uploading = true);
    try {
      final url = await uploadToTelegram(file, type);
      if (url != null) {
        await sendMessage(fileUrl: url, type: type, fileName: name);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Upload fail. 20MB se chhoti file try karo.')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Upload fail: $e')));
      }
    }
    setState(() => uploading = false);
  }

  Future<void> pickImage() async {
    final x = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 65);
    if (x == null) return;
    await uploadAndSend(File(x.path), x.name, 'image');
  }

  Future<void> pickVideo() async {
    final x = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (x == null) return;
    await uploadAndSend(File(x.path), x.name, 'video');
  }

  Future<void> pickFile() async {
    final r = await FilePicker.platform.pickFiles();
    if (r == null) return;
    await uploadAndSend(File(r.files.single.path!), r.files.single.name, 'file');
  }

  Future<void> openFile(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.receiverEmail)),
      body: Column(
        children: [
          if (uploading)
            const LinearProgressIndicator(color: Color(0xFFE91E63)),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(chatId)
                  .collection('messages')
                  .orderBy('time', descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('Message bhejo 👋'));
                }
                return ListView.builder(
                  reverse: true,
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final m = docs[i].data() as Map<String, dynamic>;
                    return _bubble(m, m['senderId'] == me.uid);
                  },
                );
              },
            ),
          ),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _bubble(Map<String, dynamic> m, bool isMe) {
    final time = m['time'] != null
        ? DateFormat('hh:mm a').format((m['time'] as Timestamp).toDate())
        : '';
    final type = m['type'] ?? 'text';

    Widget content;
    if (type == 'image') {
      content = GestureDetector(
        onTap: () => openFile(m['fileUrl']),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: m['fileUrl'],
            width: 220,
            placeholder: (_, __) => const SizedBox(
                width: 220,
                height: 150,
                child: Center(child: CircularProgressIndicator())),
            errorWidget: (_, __, ___) => const SizedBox(
                width: 220, height: 100, child: Icon(Icons.broken_image)),
          ),
        ),
      );
    } else if (type == 'video') {
      content = GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => VideoPlayerPage(url: m['fileUrl']))),
        child: Container(
          width: 220,
          height: 140,
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Icon(Icons.play_circle_fill, color: Colors.white, size: 60),
          ),
        ),
      );
    } else if (type == 'file') {
      content = InkWell(
        onTap: () => openFile(m['fileUrl']),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.insert_drive_file, color: Colors.blue, size: 32),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(m['fileName'] ?? 'file',
                overflow: TextOverflow.ellipsis),
          ),
        ]),
      );
    } else {
      content = Text(m['text'] ?? '', style: const TextStyle(fontSize: 15));
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFFFCE4EC) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            content,
            const SizedBox(height: 4),
            Text(time,
                style: const TextStyle(fontSize: 10, color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file, color: Color(0xFFE91E63)),
              onPressed: uploading
                  ? null
                  : () {
                      showModalBottomSheet(
                        context: context,
                        builder: (_) => Wrap(children: [
                          ListTile(
                            leading: const Icon(Icons.image, color: Colors.purple),
                            title: const Text('Photo'),
                            onTap: () {
                              Navigator.pop(context);
                              pickImage();
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.videocam, color: Colors.red),
                            title: const Text('Video'),
                            onTap: () {
                              Navigator.pop(context);
                              pickVideo();
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.picture_as_pdf, color: Colors.blue),
                            title: const Text('File / PDF'),
                            onTap: () {
                              Navigator.pop(context);
                              pickFile();
                            },
                          ),
                        ]),
                      );
                    },
            ),
            Expanded(
              child: TextField(
                controller: msgCtrl,
                decoration: const InputDecoration(
                  hintText: 'Message...',
                  border: InputBorder.none,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send, color: Color(0xFFE91E63)),
              onPressed: () => sendMessage(text: msgCtrl.text),
            ),
          ],
        ),
      ),
    );
  }
}

class VideoPlayerPage extends StatefulWidget {
  final String url;
  const VideoPlayerPage({super.key, required this.url});
  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late VideoPlayerController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        setState(() {});
        _ctrl.play();
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(
        child: _ctrl.value.isInitialized
            ? AspectRatio(
                aspectRatio: _ctrl.value.aspectRatio,
                child: VideoPlayer(_ctrl),
              )
            : const CircularProgressIndicator(),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFE91E63),
        onPressed: () => setState(
            () => _ctrl.value.isPlaying ? _ctrl.pause() : _ctrl.play()),
        child: Icon(_ctrl.value.isPlaying ? Icons.pause : Icons.play_arrow),
      ),
    );
  }
}
EOF

echo "✅ chat_page.dart created"
echo "✅ config.dart checked"

echo ""
echo "=========================================="
echo "🎉 SETUP COMPLETE!"
echo "=========================================="
echo ""
echo "📝 Ab ye karo:"
echo "   1. lib/config.dart kholo"
echo "   2. Token paste karo (TG_TOKEN line me)"
echo "   3. Save karo"
echo ""
echo "🚀 Fir push karo:"
echo "   git add . && git commit -m 'Telegram setup' && git push"
echo ""
