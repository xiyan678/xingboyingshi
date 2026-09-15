import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'service.dart';
import 'library.dart';

class AccountPanel extends StatelessWidget {
  final Library library;
  const AccountPanel({super.key, required this.library});
  @override
  Widget build(BuildContext context) {
    final service = AppService.instance;
    return AnimatedBuilder(
        animation: service,
        builder: (context, _) => Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const CircleAvatar(child: Icon(Icons.person)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(
                                service.loggedIn
                                    ? '${service.user!['name']}'
                                    : '登录星播账号',
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold))),
                        if (service.loggedIn)
                          TextButton(
                              onPressed: () async {
                                try {
                                  await service.logout();
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                '已退出本机；服务器令牌撤销失败，将按期限失效')));
                                  }
                                }
                              },
                              child: const Text('退出'))
                      ]),
                      const SizedBox(height: 12),
                      Text(
                          service.loggedIn
                              ? 'APP 与网站共用账号，观看进度随账号同步'
                              : '在 APP 注册即可登录网站；登录后可发送弹幕、同步观看进度',
                          style: const TextStyle(color: Colors.white60)),
                      if (!service.loggedIn)
                        FilledButton(
                            onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                    builder: (_) => const AccountPage())),
                            child: const Text('登录 / 注册')),
                      if (service.loggedIn)
                        AnimatedBuilder(
                            animation: library,
                            builder: (context, _) => Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(library.syncMessage,
                                          style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12)),
                                      TextButton(
                                          onPressed: library.syncFromAccount,
                                          child: const Text('同步观看记录'))
                                    ]))
                    ]))));
  }
}

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final name = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController(),
      verify = TextEditingController();
  final service = AppService.instance;
  bool registration = false, busy = false;
  String? message;
  Uint8List? image;
  bool get captchaRequired =>
      service
          .capabilities[registration ? 'captcha_register' : 'captcha_login'] ==
      true;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    await service.connect();
    if (!mounted) return;
    setState(() => image = null);
    if (captchaRequired) await loadCaptcha();
  }

  Future<void> loadCaptcha() async {
    try {
      final bytes = await service.captcha();
      if (mounted) setState(() => image = bytes);
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    }
  }

  Future<void> submit() async {
    if (registration &&
        (password.text.length < 8 || password.text != confirm.text)) {
      setState(() => message = '密码至少8位，两次输入需一致');
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      if (registration) {
        final msg = await service.register(
            name.text.trim(), password.text, verify.text.trim());
        if (mounted) {
          setState(() {
            registration = false;
            message = msg;
          });
        }
      } else {
        await service.login(
            name.text.trim(), password.text, verify.text.trim());
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      password.clear();
      confirm.clear();
      verify.clear();
      if (mounted) {
        setState(() => busy = false);
        if (captchaRequired) await loadCaptcha();
      }
    }
  }

  @override
  void dispose() {
    name.dispose();
    password.dispose();
    confirm.dispose();
    verify.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(registration ? '注册网站账号' : '账号登录')),
      body: AnimatedBuilder(
          animation: service,
          builder: (context, _) =>
              ListView(padding: const EdgeInsets.all(24), children: [
                const Text('一个账号，APP 与网站通用',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (!service.available) ...[
                  Text(service.connectionError ?? '正在连接网站账号服务…'),
                  TextButton(
                      onPressed: service.connecting ? null : refresh,
                      child: const Text('重试连接'))
                ],
                TextField(
                    controller: name,
                    enabled: !busy,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(labelText: '用户名')),
                const SizedBox(height: 12),
                TextField(
                    controller: password,
                    enabled: !busy,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: const InputDecoration(labelText: '密码')),
                const SizedBox(height: 12),
                if (registration) ...[
                  TextField(
                      controller: confirm,
                      enabled: !busy,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: '确认密码')),
                  const SizedBox(height: 12)
                ],
                if (captchaRequired) ...[
                  Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (image != null) Image.memory(image!, height: 60),
                        TextButton(
                            onPressed: busy ? null : loadCaptcha,
                            child: const Text('换一张验证码'))
                      ]),
                  TextField(
                      controller: verify,
                      enabled: !busy,
                      decoration: const InputDecoration(labelText: '图形验证码')),
                  const SizedBox(height: 12)
                ],
                if (message != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(message!)),
                FilledButton(
                    onPressed: busy || !service.available ? null : submit,
                    child: Text(busy
                        ? '请稍候…'
                        : registration
                            ? '注册'
                            : '登录')),
                TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            setState(() {
                              registration = !registration;
                              message = null;
                              image = null;
                              verify.clear();
                            });
                            if (captchaRequired) await loadCaptcha();
                          },
                    child: Text(registration ? '已有账号，去登录' : '没有账号，注册')),
                if (registration)
                  const Text('注册遵循网站的开放、验证码和审核设置；若网站要求短信或邮箱验证，请先在网站完成注册。',
                      style: TextStyle(color: Colors.white54, fontSize: 12))
              ])));
}
