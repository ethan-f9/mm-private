import 'package:flutter/material.dart';

/// Dialog satu kolom teks. Return null kalau dibatalkan, selain itu teks
/// yang sudah di-trim (bisa kosong).
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String? hint,
  String initial = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextInputDialog(title: title, hint: hint, initial: initial),
  );
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({
    required this.title,
    required this.hint,
    required this.initial,
  });

  final String title;
  final String? hint;
  final String initial;

  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}
