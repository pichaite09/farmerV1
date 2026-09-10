import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_session.dart';
import '../services/farmer_api.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool loginMode = true;
  bool loading = false;
  String error = '';

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => loading = true);
    try {
      final session = context.read<ApiSession>();
      if (loginMode) {
        await session.login(_username.text.trim(), _password.text);
      } else {
        await session.register(_username.text.trim(), _password.text, 'farmer');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted) {
        final apiUrl = context.read<ApiSession>().api.baseUrl;
        setState(() => error = 'เชื่อมต่อ API ไม่ได้: $apiUrl');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final green = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE2F3E5), Color(0xFFF7FBF7)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD5F0D9),
                          borderRadius: BorderRadius.circular(26),
                        ),
                        child: Icon(Icons.eco, size: 46, color: green),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'GREEN FIELD',
                        style: TextStyle(
                          letterSpacing: 2,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF176B45),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'จัดการฟาร์มของคุณให้ง่ายขึ้น',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF708078),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          loginMode ? 'เข้าสู่ระบบ' : 'สร้างบัญชีใหม่',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF18352A),
                              ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _username,
                        decoration: const InputDecoration(
                          labelText: 'อีเมล',
                          prefixIcon: Icon(Icons.alternate_email),
                        ),
                        validator: (value) =>
                            value == null ||
                                !RegExp(
                                  r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                ).hasMatch(value.trim())
                            ? 'กรุณากรอกอีเมลให้ถูกต้อง'
                            : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _password,
                        decoration: const InputDecoration(
                          labelText: 'รหัสผ่าน',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        obscureText: true,
                        validator: (value) => value == null || value.length < 8
                            ? 'รหัสผ่านต้องมี 8 ตัวอักษรขึ้นไป'
                            : null,
                      ),
                      if (error.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            error,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      const SizedBox(height: 18),
                      loading
                          ? const CircularProgressIndicator()
                          : SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: FilledButton(
                                onPressed: submit,
                                child: Text(
                                  loginMode ? 'เข้าสู่ระบบ' : 'ลงทะเบียน',
                                ),
                              ),
                            ),
                      TextButton(
                        onPressed: () => setState(() {
                          loginMode = !loginMode;
                          error = '';
                        }),
                        child: Text(
                          loginMode
                              ? 'ยังไม่มีบัญชี? สร้างบัญชีใหม่'
                              : 'มีบัญชีอยู่แล้ว? เข้าสู่ระบบ',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
