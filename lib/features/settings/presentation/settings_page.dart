import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:personal_finance_manager/core/ai/ai_config.dart';
import 'package:personal_finance_manager/core/ai/llm_client.dart';
import 'package:personal_finance_manager/core/utils/ui_helpers.dart';
import 'package:personal_finance_manager/features/settings/data/ai_providers.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _baseUrl = TextEditingController();
  final _parserModel = TextEditingController();
  final _advisorModel = TextEditingController();
  final _apiKey = TextEditingController();
  bool _loading = true;
  bool _hasKey = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _parserModel.dispose();
    _advisorModel.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final config = await ref.read(settingsRepositoryProvider).loadAiConfig();
    final key = await ref.read(secureStoreProvider).readAiKey();
    if (!mounted) return;
    setState(() {
      _baseUrl.text = config.baseUrl;
      _parserModel.text = config.parserModel;
      _advisorModel.text = config.advisorModel;
      _hasKey = key != null && key.isNotEmpty;
      _loading = false;
    });
  }

  /// Return true kalau berhasil disimpan.
  Future<bool> _save() async {
    final urlError = AiConfig.validateBaseUrl(_baseUrl.text);
    if (urlError != null) {
      showSnack(context, urlError);
      return false;
    }
    final parser = _parserModel.text.trim();
    final advisor = _advisorModel.text.trim();
    if (parser.isEmpty || advisor.isEmpty) {
      showSnack(context, 'Nama model tidak boleh kosong');
      return false;
    }

    final settings = ref.read(settingsRepositoryProvider);
    final store = ref.read(secureStoreProvider);

    await settings.saveAiConfig(
      AiConfig(
        baseUrl: AiConfig.normalizeBaseUrl(_baseUrl.text),
        parserModel: parser,
        advisorModel: advisor,
      ),
    );

    final newKey = _apiKey.text.trim();
    if (newKey.isNotEmpty) {
      await store.writeAiKey(newKey);
      _apiKey.clear();
    }
    final key = await store.readAiKey();
    if (!mounted) return false;
    ref.invalidate(aiConfigProvider);
    setState(() => _hasKey = key != null && key.isNotEmpty);
    return true;
  }

  Future<void> _saveOnly() async {
    setState(() => _busy = true);
    try {
      final ok = await _save();
      if (ok && mounted) showSnack(context, 'Tersimpan');
    } catch (e) {
      if (mounted) showSnack(context, errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    setState(() => _busy = true);
    try {
      final ok = await _save();
      if (!ok) return;
      final reply = await ref.read(llmClientProvider).complete(
        role: AiRole.parser,
        messages: const [
          {'role': 'user', 'content': 'Balas dengan satu kata saja: ok'},
        ],
      );
      final shown = reply.length > 60 ? reply.substring(0, 60) : reply;
      if (mounted) showSnack(context, 'Terhubung. Balasan: $shown');
    } catch (e) {
      if (mounted) showSnack(context, 'Gagal: ${errorMessage(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteKey() async {
    await ref.read(secureStoreProvider).deleteAiKey();
    if (!mounted) return;
    setState(() => _hasKey = false);
    showSnack(context, 'API key dihapus');
  }

  void _resetDefaults() {
    setState(() {
      _baseUrl.text = AiConfig.defaultBaseUrl;
      _parserModel.text = AiConfig.defaultModel;
      _advisorModel.text = AiConfig.defaultModel;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Provider AI', style: text.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Bisa provider apa saja yang mendukung endpoint '
                  'chat/completions gaya OpenAI.',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _baseUrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    helperText: 'Tanpa /chat/completions. Wajib https.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _apiKey,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'API key',
                    helperText: _hasKey
                        ? 'Tersimpan di Keystore. Kosongkan kalau tidak diganti.'
                        : 'Belum diatur.',
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_hasKey)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _busy ? null : _deleteKey,
                      child: const Text('Hapus API key'),
                    ),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _parserModel,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Model untuk Isi dengan AI',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _advisorModel,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Model untuk advisor',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _busy ? null : _resetDefaults,
                    child: const Text('Kembalikan ke default (Groq)'),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _saveOnly,
                  child: const Text('Simpan'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _busy ? null : _test,
                  child: const Text('Simpan dan tes koneksi'),
                ),
                const SizedBox(height: 24),
                Text(
                  'Yang dikirim ke provider: teks yang kamu ketik di '
                  '"Isi dengan AI" beserta nama akun dan kategori. Saldo dan '
                  'riwayat transaksi tidak dikirim.',
                  style: text.bodySmall,
                ),
              ],
            ),
    );
  }
}
