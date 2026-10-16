import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

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

  Future<void> sendMessage({String? text, String? fileUrl, String? type, String? fileName}) async {
    if ((text == null || text.trim().isEmpty) && fileUrl == null) return;
    await FirebaseFirestore.instance
        .collection('chats').doc(chatId).collection('messages').add({
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
      final ref = FirebaseStorage.instance.ref(
          'chat_files/${DateTime.now().millisecondsSinceEpoch}_$name');
      await ref.putFile(file);
      final url = await ref.getDownloadURL();
      await sendMessage(fileUrl: url, type: type, fileName: name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Upload fail: $e')));
      }
    }
    setState(() => uploading = false);
  }

  Future<void> pickImage() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
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
          if (uploading) const LinearProgressIndicator(color: Color(0xFFE91E63)),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats').doc(chatId).collection('messages')
                  .orderBy('time', descending: true).snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) return const Center(child: Text('Message bhejo 👋'));
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
          child: CachedNetworkImage(imageUrl: m['fileUrl'], width: 220),
        ),
      );
    } else if (type == 'video') {
      content = GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => VideoPlayerPage(url: m['fileUrl']))),
        child: Container(
          width: 220, height: 140,
          color: Colors.black87,
          child: const Icon(Icons.play_circle_fill, color: Colors.white, size: 60),
        ),
      );
    } else if (type == 'file') {
      content = InkWell(
        onTap: () => openFile(m['fileUrl']),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.insert_drive_file, color: Colors.blue, size: 32),
          const SizedBox(width: 8),
          Flexible(child: Text(m['fileName'] ?? 'file', overflow: TextOverflow.ellipsis)),
        ]),
      );
    } else {
      content = Text(m['text'] ?? '');
    }
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFFFCE4EC) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            content,
            const SizedBox(height: 4),
            Text(time, style: const TextStyle(fontSize: 10, color: Colors.black54)),
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
              onPressed: uploading ? null : () {
                showModalBottomSheet(
                  context: context,
                  builder: (_) => Wrap(children: [
                    ListTile(
                      leading: const Icon(Icons.image, color: Colors.purple),
                      title: const Text('Photo'),
                      onTap: () { Navigator.pop(context); pickImage(); },
                    ),
                    ListTile(
                      leading: const Icon(Icons.videocam, color: Colors.red),
                      title: const Text('Video'),
                      onTap: () { Navigator.pop(context); pickVideo(); },
                    ),
                    ListTile(
                      leading: const Icon(Icons.picture_as_pdf, color: Colors.blue),
                      title: const Text('File / PDF'),
                      onTap: () { Navigator.pop(context); pickFile(); },
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
      ..initialize().then((_) { setState(() {}); _ctrl.play(); });
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(
        child: _ctrl.value.isInitialized
            ? AspectRatio(aspectRatio: _ctrl.value.aspectRatio, child: VideoPlayer(_ctrl))
            : const CircularProgressIndicator(),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFE91E63),
        onPressed: () => setState(() => _ctrl.value.isPlaying ? _ctrl.pause() : _ctrl.play()),
        child: Icon(_ctrl.value.isPlaying ? Icons.pause : Icons.play_arrow),
      ),
    );
  }
}
