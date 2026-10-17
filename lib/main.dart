// ============================================================
// MTG PRO - App multi-compañía (Fase 2: trabajos, clientes, calendario)
// ------------------------------------------------------------
// Flujo (idea de Maikel):
//  1. La compañía se registra sola (queda "pending").
//  2. Maikel (super-admin) la activa.
//  3. La compañía crea los users de sus trabajadores con
//     contraseña TEMPORAL.
//  4. El trabajador entra con user + temporal y crea su
//     propia contraseña.
//  5. De ahí en adelante el trabajador solo ve user + contraseña.
//
// Setup en la PC:
//   flutter create .  (dentro de la carpeta mtg-pro)
//   flutterfire configure  (proyecto the-handyman-dfeae)
//   flutter pub add firebase_core firebase_auth cloud_firestore shared_preferences
//   flutter run
// ============================================================

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

// TODO: reemplazar con tu firebase_options.dart (flutterfire configure)
import 'firebase_options.dart';

/// Correo del super-admin (Maikel).
const String kSuperAdminEmail = 'maikelramirez55@gmail.com';

/// Dominio interno para convertir "user" en email de Firebase Auth.
String _emailForUser(String user) =>
    user.contains('@') ? user.trim() : '${user.trim()}@workers.mtgpro.app';

/// Genera contraseña temporal de 8 caracteres.
String _tempPassword() {
  const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
  final r = Random.secure();
  return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
}

// ==================== MODELOS FASE 2 ====================

const Map<String, String> kJobStatus = {
  'pendiente': '🕐 Pendiente',
  'en_curso': '🔨 En curso',
  'completado': '✅ Completado',
  'cancelado': '❌ Cancelado',
};

class Job {
  final String id;
  final String companyId;
  final String clientId;
  final String clientName;
  final String title;
  final String description;
  final String address;
  final String status;
  final DateTime? scheduledDate;
  final String assignedTo;
  final String assignedName;
  final double price;
  final String notes;
  Job({
    required this.id,
    required this.companyId,
    this.clientId = '',
    this.clientName = '',
    required this.title,
    this.description = '',
    this.address = '',
    this.status = 'pendiente',
    this.scheduledDate,
    this.assignedTo = '',
    this.assignedName = '',
    this.price = 0,
    this.notes = '',
  });
  static Job fromMap(String id, Map<String, dynamic> m) => Job(
        id: id,
        companyId: m['companyId'] as String? ?? '',
        clientId: m['clientId'] as String? ?? '',
        clientName: m['clientName'] as String? ?? '',
        title: m['title'] as String? ?? '',
        description: m['description'] as String? ?? '',
        address: m['address'] as String? ?? '',
        status: m['status'] as String? ?? 'pendiente',
        scheduledDate: (m['scheduledDate'] as Timestamp?)?.toDate(),
        assignedTo: m['assignedTo'] as String? ?? '',
        assignedName: m['assignedName'] as String? ?? '',
        price: (m['price'] as num?)?.toDouble() ?? 0,
        notes: m['notes'] as String? ?? '',
      );
  Map<String, dynamic> toMap() => {
        'companyId': companyId,
        'clientId': clientId,
        'clientName': clientName,
        'title': title,
        'description': description,
        'address': address,
        'status': status,
        'scheduledDate':
            scheduledDate != null ? Timestamp.fromDate(scheduledDate!) : null,
        'assignedTo': assignedTo,
        'assignedName': assignedName,
        'price': price,
        'notes': notes,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

class Client {
  final String id;
  final String companyId;
  final String name;
  final String phone;
  final String email;
  final String address;
  final String notes;
  Client({
    required this.id,
    required this.companyId,
    required this.name,
    this.phone = '',
    this.email = '',
    this.address = '',
    this.notes = '',
  });
  static Client fromMap(String id, Map<String, dynamic> m) => Client(
        id: id,
        companyId: m['companyId'] as String? ?? '',
        name: m['name'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        email: m['email'] as String? ?? '',
        address: m['address'] as String? ?? '',
        notes: m['notes'] as String? ?? '',
      );
  Map<String, dynamic> toMap() => {
        'companyId': companyId,
        'name': name,
        'phone': phone,
        'email': email,
        'address': address,
        'notes': notes,
        'createdAt': FieldValue.serverTimestamp(),
      };
}

String fmtDate(DateTime? d) {
  if (d == null) return 'Sin fecha';
  const ms = ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
  return '${d.day} ${ms[d.month - 1]} ${d.year}';
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MtgProApp());
}

class MtgProApp extends StatelessWidget {
  const MtgProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MTG Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1565C0)),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

// ==================== AUTH GATE ====================

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (c, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (!snap.hasData) return const WelcomeScreen();
        return const SessionLoader();
      },
    );
  }
}

/// Carga el perfil del usuario y decide a dónde va.
class SessionLoader extends StatelessWidget {
  const SessionLoader({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FutureBuilder<DocumentSnapshot>(
      future:
          FirebaseFirestore.instance.collection('users').doc(uid).get(),
      builder: (c, snap) {
        if (!snap.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final d = snap.data!;
        if (!d.exists) {
          // Cuenta de Auth existente sin perfil: vincularla a una compañía.
          return const LinkAccountScreen();
        }
        final u = Map<String, dynamic>.from(d.data() as Map);
        // ¿Debe cambiar la contraseña temporal?
        if (u['mustChangePassword'] == true) {
          return const ChangePasswordScreen(forced: true);
        }
        final role = u['role'] as String? ?? 'worker';
        final email =
            FirebaseAuth.instance.currentUser!.email ?? '';
        if (email.toLowerCase() == kSuperAdminEmail) {
          return const SuperAdminHome();
        }
        if (role == 'admin') return const CompanyAdminHome();
        return const WorkerHome();
      },
    );
  }
}

// ==================== BIENVENIDA ====================

Widget _mtgFeature(String emoji, String title, String sub) {
  return Padding(
    padding:
        const EdgeInsets.symmetric(horizontal: 44, vertical: 7),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.16),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
              child: Text(emoji,
                  style: const TextStyle(fontSize: 24))),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(sub,
                  style: const TextStyle(
                      color: Color(0xFFD7E7FA),
                      fontSize: 13)),
            ],
          ),
        ),
      ],
    ),
  );
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Parte superior: marca sobre gradiente navy.
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF0F2A4A),
                    Color(0xFF16467E),
                    Color(0xFF1A6FD4)
                  ],
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black
                                  .withOpacity(0.25),
                              blurRadius: 24,
                              offset:
                                  const Offset(0, 8)),
                        ],
                      ),
                      child: const Center(
                          child: Text('🔧',
                              style:
                                  TextStyle(fontSize: 52))),
                    ),
                    const SizedBox(height: 16),
                    const Text('MTG Pro',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 10),
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        'La app de tu compañía handyman',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Color(0xFFD7E7FA),
                            fontSize: 17,
                            height: 1.4),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _mtgFeature('🔧', 'Trabajos',
                        'Crea, asigna y sigue cada trabajo'),
                    _mtgFeature('👥', 'Clientes y equipo',
                        'Directorio con historial de trabajos'),
                    _mtgFeature('📅', 'Calendario',
                        'Tu agenda de un vistazo'),
                  ],
                ),
              ),
            ),
          ),
          // Panel inferior blanco con botones.
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.fromLTRB(24, 24, 24, 32),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(28),
                topRight: Radius.circular(28),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor:
                            const Color(0xFFF5851F),
                        padding:
                            const EdgeInsets.symmetric(
                                vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(
                                    12))),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const RegisterCompanyScreen())),
                    child: const Text(
                        'Registrar mi compañía',
                        style: TextStyle(fontSize: 17)),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(
                                vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(
                                    12)),
                        side: const BorderSide(
                            color: Color(0xFFD0D9E3))),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                const LoginScreen())),
                    child: const Text('Entrar',
                        style: TextStyle(
                            fontSize: 17,
                            color: Color(0xFF0F2A4A))),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Sin tarjeta · Tu cuenta se activa por WhatsApp',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Color(0xFF8A97A8),
                        fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== REGISTRO DE COMPAÑÍA ====================

class RegisterCompanyScreen extends StatefulWidget {
  const RegisterCompanyScreen({super.key});
  @override
  State<RegisterCompanyScreen> createState() =>
      _RegisterCompanyScreenState();
}

class _RegisterCompanyScreenState extends State<RegisterCompanyScreen> {
  final _companyCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _busy = false;

  Future<void> _register() async {
    final company = _companyCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (company.isEmpty ||
        name.isEmpty ||
        email.isEmpty ||
        pass.length < 6) {
      _msg('Completa todo (contraseña mínimo 6 caracteres).');
      return;
    }
    setState(() => _busy = true);
    try {
      final cred = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: pass);
      final uid = cred.user!.uid;
      final db = FirebaseFirestore.instance;
      // Compañía (queda pending hasta que Maikel la active).
      final compRef = db.collection('companies').doc();
      await compRef.set({
        'id': compRef.id,
        'name': company,
        'status': 'pending',
        'adminUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      // Usuario admin de la compañía.
      await db.collection('users').doc(uid).set({
        'uid': uid,
        'companyId': compRef.id,
        'username': email.split('@').first,
        'displayName': name,
        'role': 'admin',
        'mustChangePassword': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          title: const Text('¡Registro listo!'),
          content: const Text(
              'Tu compañía quedó en revisión. Te avisaremos cuando esté activa para que puedas crear los usuarios de tus trabajadores.'),
          actions: [
            FilledButton(
                onPressed: () {
                  Navigator.pop(c);
                  Navigator.pop(context);
                },
                child: const Text('Entendido')),
          ],
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        _msg('Este correo ya está registrado. Usa "Entrar" en su lugar.');
      } else {
        _msg('No se pudo registrar: ${e.message}');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _msg(String t) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar compañía')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
                controller: _companyCtrl,
                decoration: const InputDecoration(
                    labelText: 'Nombre de la compañía *',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Tu nombre *',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                    labelText: 'Correo *',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: _passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Contraseña * (mínimo 6)',
                    border: OutlineInputBorder())),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: _busy ? null : _register,
              child: _busy
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== VINCULAR CUENTA EXISTENTE ====================
/// Para correos que ya existen en Auth pero sin perfil en la app.

class LinkAccountScreen extends StatefulWidget {
  const LinkAccountScreen({super.key});
  @override
  State<LinkAccountScreen> createState() => _LinkAccountScreenState();
}

class _LinkAccountScreenState extends State<LinkAccountScreen> {
  final _companyCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _busy = false;

  Future<void> _link() async {
    final company = _companyCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    if (company.isEmpty || name.isEmpty) {
      _msg('Completa el nombre de la compañía y tu nombre.');
      return;
    }
    setState(() => _busy = true);
    try {
      final u = FirebaseAuth.instance.currentUser!;
      final db = FirebaseFirestore.instance;
      final compRef = db.collection('companies').doc();
      await compRef.set({
        'id': compRef.id,
        'name': company,
        'status': 'pending',
        'adminUid': u.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await db.collection('users').doc(u.uid).set({
        'uid': u.uid,
        'companyId': compRef.id,
        'username': (u.email ?? '').split('@').first,
        'displayName': name,
        'role': 'admin',
        'mustChangePassword': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (_) => false);
    } catch (e) {
      _msg('No se pudo: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _msg(String t) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('Vincular cuenta')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Tu correo $email ya existe. Vincúlalo a tu compañía:',
                style: const TextStyle(fontSize: 15)),
            const SizedBox(height: 16),
            TextField(
                controller: _companyCtrl,
                decoration: const InputDecoration(
                    labelText: 'Nombre de la compañía *',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Tu nombre *',
                    border: OutlineInputBorder())),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: _busy ? null : _link,
              child: _busy
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Vincular'),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== LOGIN ====================

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _busy = false;

  Future<void> _login() async {
    final user = _userCtrl.text.trim();
    final pass = _passCtrl.text;
    if (user.isEmpty || pass.isEmpty) {
      _msg('Escribe tu usuario y contraseña.');
      return;
    }
    setState(() => _busy = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailForUser(user), password: pass);
      // Verificar que la compañía esté activa (si no es super-admin).
      final u = FirebaseAuth.instance.currentUser!;
      if (u.email?.toLowerCase() != kSuperAdminEmail) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(u.uid)
            .get();
        final data =
            doc.exists ? Map<String, dynamic>.from(doc.data() as Map) : {};
        final compId = data['companyId'] as String?;
        if (compId != null) {
          final comp = await FirebaseFirestore.instance
              .collection('companies')
              .doc(compId)
              .get();
          final status = comp.exists
              ? (Map<String, dynamic>.from(comp.data() as Map)['status']
                      as String?)
                  : null;
          if (status == 'suspended') {
            await FirebaseAuth.instance.signOut();
            _msg('Tu compañía está suspendida. Habla con el administrador.');
            return;
          }
          if (status == 'pending' &&
              (data['role'] as String? ?? '') != 'admin') {
            await FirebaseAuth.instance.signOut();
            _msg('Tu compañía aún está en revisión.');
            return;
          }
        }
      }
      if (mounted) Navigator.pop(context); // AuthGate toma el control
    } on FirebaseAuthException catch (e) {
      _msg('No se pudo entrar: ${_friendly(e.code)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(String code) {
    switch (code) {
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Usuario o contraseña incorrectos.';
      default:
        return code;
    }
  }

  void _msg(String t) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrar')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Solo tu usuario y contraseña.',
              style: TextStyle(color: Colors.grey, fontSize: 15),
            ),
            const SizedBox(height: 16),
            TextField(
                controller: _userCtrl,
                autocorrect: false,
                decoration: const InputDecoration(
                    labelText: 'Usuario *',
                    hintText: 'Ej: juan.perez',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: _passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Contraseña *',
                    border: OutlineInputBorder())),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: _busy ? null : _login,
              child: _busy
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Entrar'),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== CAMBIO DE CONTRASEÑA ====================

class ChangePasswordScreen extends StatefulWidget {
  final bool forced;
  const ChangePasswordScreen({super.key, this.forced = false});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _p1 = TextEditingController();
  final _p2 = TextEditingController();
  bool _busy = false;

  Future<void> _save() async {
    if (_p1.text.length < 6) {
      _msg('Mínimo 6 caracteres.');
      return;
    }
    if (_p1.text != _p2.text) {
      _msg('No coinciden.');
      return;
    }
    setState(() => _busy = true);
    try {
      final u = FirebaseAuth.instance.currentUser!;
      await u.updatePassword(_p1.text);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(u.uid)
          .update({
        'mustChangePassword': false,
        'tempPassword': FieldValue.delete(),
      });
      if (mounted) {
        if (widget.forced) {
          // Recargar sesión: AuthGate decide a dónde va.
          Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const AuthGate()),
              (_) => false);
        } else {
          Navigator.pop(context);
        }
      }
    } on FirebaseAuthException catch (e) {
      _msg('No se pudo: ${e.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _msg(String t) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(t)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('Crea tu contraseña'),
          automaticallyImplyLeading: !widget.forced),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Estás usando una contraseña temporal. Crea la tuya propia:',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 16),
            TextField(
                controller: _p1,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Nueva contraseña *',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: _p2,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Repítela *',
                    border: OutlineInputBorder())),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Guardar contraseña'),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== HOME: ADMIN DE COMPAÑÍA ====================

// ==================== HOME PRINCIPAL (tabs) ====================

class CompanyAdminHome extends StatelessWidget {
  const CompanyAdminHome({super.key});
  @override
  Widget build(BuildContext context) => const MainHome(isAdmin: true);
}

class WorkerHome extends StatelessWidget {
  const WorkerHome({super.key});
  @override
  Widget build(BuildContext context) => const MainHome(isAdmin: false);
}

class MainHome extends StatefulWidget {
  final bool isAdmin;
  const MainHome({super.key, required this.isAdmin});
  @override
  State<MainHome> createState() => _MainHomeState();
}

class _MainHomeState extends State<MainHome> {
  int _tab = 0;
  String _compId = '';
  String _compName = '';
  String _name = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    String compName = '';
    String compId = '';
    String name = '';
    if (doc.exists) {
      final m =
          Map<String, dynamic>.from(doc.data() as Map);
      compId = m['companyId'] as String? ?? '';
      name = m['displayName'] as String? ?? '';
      if (compId.isNotEmpty) {
        final cdoc = await FirebaseFirestore.instance
            .collection('companies')
            .doc(compId)
            .get();
        if (cdoc.exists) {
          compName = (Map<String, dynamic>.from(
                  cdoc.data() as Map)['name'] as String?) ??
              '';
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _compId = compId;
      _compName = compName;
      _name = name;
      _loading = false;
    });
  }

  void _go(int i) => setState(() => _tab = i);

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final tabs = widget.isAdmin
        ? ['🏠', '🔧', '👥', '📅', '⚙️']
        : ['🏠', '🔧', '📅', '👤'];
    final labels = widget.isAdmin
        ? ['Inicio', 'Trabajos', 'Clientes', 'Calendario', 'Equipo']
        : ['Inicio', 'Trabajos', 'Calendario', 'Cuenta'];
    final pages = widget.isAdmin
        ? [
            DashboardTab(
                companyId: _compId,
                companyName: _compName,
                userName: _name,
                isAdmin: true,
                uid: '',
                onGo: _go),
            JobsScreen(companyId: _compId, isAdmin: true, uid: ''),
            ClientsScreen(companyId: _compId, isAdmin: true),
            CalendarScreen(companyId: _compId, isAdmin: true, uid: ''),
            TeamTab(companyId: _compId),
          ]
        : [
            DashboardTab(
                companyId: _compId,
                companyName: _compName,
                userName: _name,
                isAdmin: false,
                uid: uid,
                onGo: _go),
            JobsScreen(
                companyId: _compId, isAdmin: false, uid: uid),
            CalendarScreen(
                companyId: _compId, isAdmin: false, uid: uid),
            AccountTab(name: _name),
          ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0
            ? '🔧 MTG Pro'
            : (widget.isAdmin
                ? '🔧 ${labels[_tab]}'
                : labels[_tab])),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Cambiar contraseña',
            icon: const Icon(Icons.lock_outline),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ChangePasswordScreen())),
          ),
          IconButton(
            tooltip: 'Salir',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: pages[_tab],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _tab = i),
        items: [
          for (var i = 0; i < tabs.length; i++)
            BottomNavigationBarItem(
                icon: Text(tabs[i], style: const TextStyle(fontSize: 22)),
                label: labels[i]),
        ],
      ),
    );
  }
}

/// Contenido de la pestaña Equipo (antes CompanyAdminHome).
class TeamTab extends StatelessWidget {
  final String companyId;
  const TeamTab({super.key, required this.companyId});

  Future<void> _deleteWorker(
      BuildContext context, Map<String, dynamic> w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eliminar trabajador'),
        content: Text(
            '¿Eliminar a ${w['displayName']}? Su acceso quedará bloqueado.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(w['uid'] as String)
        .delete();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('companyId', isEqualTo: companyId)
          .snapshots(),
      builder: (c, s) {
        if (s.hasError) {
          return Center(child: Text('Error: ${s.error}'));
        }
        if (!s.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final workers = s.data!.docs
            .map((d) =>
                Map<String, dynamic>.from(d.data() as Map))
            .where((u) => u['role'] != 'admin')
            .toList();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Trabajadores',
                style:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (workers.isEmpty)
              const Card(
                  child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'Sin trabajadores todavía. Créales su usuario con el botón ＋.'))),
            ...workers.map((w) => Card(
                  child: ListTile(
                    leading: CircleAvatar(
                        child: Text(
                            (w['displayName'] as String? ?? '?')
                                .substring(0, 1)
                                .toUpperCase())),
                    title: Text(w['displayName'] as String? ?? ''),
                    subtitle: Text(
                        'Usuario: ${w['username'] ?? ''}${w['mustChangePassword'] == true ? ' · ⏳ temporal' : ''}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (w['mustChangePassword'] == true)
                          IconButton(
                            tooltip: 'Ver contraseña temporal',
                            icon: const Icon(Icons.key,
                                color: Colors.blue),
                            onPressed: () => showDialog(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: Text(
                                    'Temporal de ${w['displayName']}'),
                                content: SelectableText(
                                    'Usuario: ${w['username']}\nContraseña temporal: ${w['tempPassword'] ?? '(no guardada)'}'),
                                actions: [
                                  FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(c),
                                      child: const Text('Cerrar')),
                                ],
                              ),
                            ),
                          ),
                        IconButton(
                          tooltip: 'Eliminar',
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red),
                          onPressed: () =>
                              _deleteWorker(context, w),
                        ),
                      ],
                    ),
                  ),
                )),
          ],
        );
      },
    );
  }
}

/// Cuenta del trabajador (cambiar contraseña ya está en el AppBar).
class AccountTab extends StatelessWidget {
  final String name;
  const AccountTab({super.key, required this.name});
  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 12),
        const Center(
            child:
                Text('👤', style: TextStyle(fontSize: 64))),
        const SizedBox(height: 12),
        Center(
            child: Text(name,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold))),
        const SizedBox(height: 4),
        Center(
            child: Text(email,
                style:
                    const TextStyle(color: Colors.grey))),
        const SizedBox(height: 24),
        Card(
          child: ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Cambiar contraseña'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const ChangePasswordScreen())),
          ),
        ),
      ],
    );
  }
}

// ==================== HOME: SUPER-ADMIN ====================

class SuperAdminHome extends StatelessWidget {
  const SuperAdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🏢 Compañías'),
        actions: [
          IconButton(
            tooltip: 'Salir',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('companies')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (c, s) {
          if (s.hasError) {
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Error cargando: ${s.error}',
                        textAlign: TextAlign.center)));
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final comps = s.data!.docs
              .map((d) =>
                  Map<String, dynamic>.from(d.data() as Map))
              .toList();
          if (comps.isEmpty) {
            return const Center(
                child: Text('Sin compañías registradas.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: comps.length,
            itemBuilder: (c, i) {
              final co = comps[i];
              final st = co['status'] as String? ?? 'pending';
              final badge = st == 'active'
                  ? '✅ Activa'
                  : st == 'suspended'
                      ? '🚫 Suspendida'
                      : '⏳ En revisión';
              return Card(
                child: ListTile(
                  title: Text(co['name'] as String? ?? ''),
                  subtitle: Text(badge),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (st != 'active')
                        IconButton(
                          tooltip: 'Activar',
                          icon: const Icon(Icons.check_circle,
                              color: Colors.green),
                          onPressed: () => _setStatus(
                              co['id'] as String, 'active'),
                        ),
                      if (st == 'active')
                        IconButton(
                          tooltip: 'Suspender',
                          icon: const Icon(Icons.block,
                              color: Colors.red),
                          onPressed: () => _setStatus(
                              co['id'] as String, 'suspended'),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _setStatus(String id, String status) {
    return FirebaseFirestore.instance
        .collection('companies')
        .doc(id)
        .update({'status': status});
  }
}


// ==================== DASHBOARD (estilo Walkthrough) ====================

class DashboardTab extends StatelessWidget {
  final String companyId;
  final String companyName;
  final String userName;
  final bool isAdmin;
  final String uid;
  final void Function(int) onGo;
  const DashboardTab({
    super.key,
    required this.companyId,
    required this.companyName,
    required this.userName,
    required this.isAdmin,
    required this.uid,
    required this.onGo,
  });

  @override
  Widget build(BuildContext context) {
    Query q = FirebaseFirestore.instance
        .collection('jobs')
        .where('companyId', isEqualTo: companyId);
    if (!isAdmin) q = q.where('assignedTo', isEqualTo: uid);
    return StreamBuilder<QuerySnapshot>(
      stream: q.snapshots(),
      builder: (c, snap) {
        final jobs = snap.hasData
            ? snap.data!.docs
                .map((d) => Job.fromMap(d.id,
                    Map<String, dynamic>.from(
                        d.data() as Map)))
                .toList()
            : <Job>[];
        final now = DateTime.now();
        final today = jobs
            .where((j) =>
                j.scheduledDate != null &&
                j.scheduledDate!.year == now.year &&
                j.scheduledDate!.month == now.month &&
                j.scheduledDate!.day == now.day &&
                j.status != 'completado' &&
                j.status != 'cancelado')
            .toList();
        final pend =
            jobs.where((j) => j.status == 'pendiente').length;
        final curso =
            jobs.where((j) => j.status == 'en_curso').length;
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // Cabecera con compañía
            Card(
              color: const Color(0xFF1565C0),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      companyName.isNotEmpty
                          ? companyName
                          : 'MTG Pro',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Hola, $userName · ${fmtDate(now)}',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Estadísticas
            Row(
              children: [
                _stat('🕐', '$pend', 'Pendientes',
                    Colors.orange),
                _stat('🔨', '$curso', 'En curso',
                    Colors.blue),
                _stat('📅', '${today.length}',
                    'Hoy', Colors.green),
              ],
            ),
            const SizedBox(height: 12),
            // Menú estilo Walkthrough
            _menuCard(
              context,
              '🔧',
              'Trabajos',
              '${jobs.length} en total · $pend pendientes',
              () => onGo(1),
            ),
            if (isAdmin)
              _menuCard(
                context,
                '👥',
                'Clientes',
                'Directorio de clientes',
                () => onGo(2),
              ),
            _menuCard(
              context,
              '📅',
              'Calendario',
              'Agenda de trabajos',
              () => onGo(isAdmin ? 3 : 2),
            ),
            if (isAdmin)
              _menuCard(
                context,
                '⚙️',
                'Equipo',
                'Trabajadores y accesos',
                () => onGo(4),
              ),
            if (today.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: 4, vertical: 8),
                child: Text('📌 Hoy',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
              ),
              ...today.map((j) => Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                          child: Text('🔧')),
                      title: Text(j.title,
                          style: const TextStyle(
                              fontWeight:
                                  FontWeight.bold)),
                      subtitle: Text(
                          '${kJobStatus[j.status] ?? ""}${j.clientName.isNotEmpty ? " · " + j.clientName : ""}'),
                      trailing: const Icon(
                          Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              JobDetailScreen(
                            job: j,
                            isAdmin: isAdmin,
                          ),
                        ),
                      ),
                    ),
                  )),
            ],
          ],
        );
      },
    );
  }

  Widget _stat(
      String emoji, String num, String label, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              Text(emoji,
                  style:
                      const TextStyle(fontSize: 24)),
              const SizedBox(height: 4),
              Text(num,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color)),
              Text(label,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuCard(BuildContext context, String emoji,
      String title, String subtitle, VoidCallback onTap) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          radius: 24,
          backgroundColor:
              const Color(0xFF1565C0).withOpacity(0.12),
          child: Text(emoji,
              style:
                  const TextStyle(fontSize: 24)),
        ),
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17)),
        subtitle: Text(subtitle),
        trailing:
            const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

// ==================== FASE 2: TRABAJOS ====================

class JobsScreen extends StatefulWidget {
  final String companyId;
  final bool isAdmin;
  final String uid;
  const JobsScreen(
      {super.key,
      required this.companyId,
      required this.isAdmin,
      required this.uid});
  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  String _filter = 'todos';

  @override
  Widget build(BuildContext context) {
    Query q = FirebaseFirestore.instance
        .collection('jobs')
        .where('companyId', isEqualTo: widget.companyId)
        .orderBy('createdAt', descending: true);
    if (!widget.isAdmin) {
      q = q.where('assignedTo', isEqualTo: widget.uid);
    }
    return Scaffold(
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _chip('todos', 'Todos'),
                _chip('pendiente', '🕐 Pendientes'),
                _chip('en_curso', '🔨 En curso'),
                _chip('completado', '✅ Completados'),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: q.snapshots(),
              builder: (c, snap) {
                if (snap.hasError) {
                  return Center(
                      child: Text('Error: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(
                      child: CircularProgressIndicator());
                }
                var jobs = snap.data!.docs
                    .map((d) => Job.fromMap(
                        d.id,
                        Map<String, dynamic>.from(
                            d.data() as Map)))
                    .toList();
                if (_filter != 'todos') {
                  jobs = jobs
                      .where((j) => j.status == _filter)
                      .toList();
                }
                if (jobs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Sin trabajos aquí todavía.',
                        style:
                            TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: jobs.length,
                  itemBuilder: (c, i) {
                    final j = jobs[i];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              _statusColor(j.status).withOpacity(0.15),
                          child: Text(
                            _statusEmoji(j.status),
                            style:
                                const TextStyle(fontSize: 20),
                          ),
                        ),
                        title: Text(j.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          '${j.clientName.isNotEmpty ? j.clientName + " · " : ""}${fmtDate(j.scheduledDate)}${j.assignedName.isNotEmpty ? " · 👷 " + j.assignedName : ""}',
                          maxLines: 2,
                        ),
                        trailing: j.price > 0
                            ? Text('\$${j.price.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15))
                            : null,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => JobDetailScreen(
                              job: j,
                              isAdmin: widget.isAdmin,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => JobFormScreen(
                    companyId: widget.companyId,
                  ),
                ),
              ),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _chip(String v, String label) {
    final on = _filter == v;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: on,
        onSelected: (_) => setState(() => _filter = v),
      ),
    );
  }

  String _statusEmoji(String st) {
    switch (st) {
      case 'pendiente':
        return '🕐';
      case 'en_curso':
        return '🔨';
      case 'completado':
        return '✅';
      case 'cancelado':
        return '❌';
      default:
        return '🔧';
    }
  }

  Color _statusColor(String st) {
    switch (st) {
      case 'pendiente':
        return Colors.orange;
      case 'en_curso':
        return Colors.blue;
      case 'completado':
        return Colors.green;
      case 'cancelado':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

class JobFormScreen extends StatefulWidget {
  final String companyId;
  final Job? job;
  const JobFormScreen(
      {super.key, required this.companyId, this.job});
  @override
  State<JobFormScreen> createState() => _JobFormScreenState();
}

class _JobFormScreenState extends State<JobFormScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _clientId = '';
  String _clientName = '';
  String _assignedTo = '';
  String _assignedName = '';
  String _status = 'pendiente';
  DateTime? _date;
  bool _saving = false;
  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _workers = [];

  @override
  void initState() {
    super.initState();
    final j = widget.job;
    if (j != null) {
      _titleCtrl.text = j.title;
      _descCtrl.text = j.description;
      _addrCtrl.text = j.address;
      _priceCtrl.text =
          j.price > 0 ? j.price.toStringAsFixed(0) : '';
      _notesCtrl.text = j.notes;
      _clientId = j.clientId;
      _clientName = j.clientName;
      _assignedTo = j.assignedTo;
      _assignedName = j.assignedName;
      _status = j.status;
      _date = j.scheduledDate;
    }
    _loadLists();
  }

  Future<void> _loadLists() async {
    final db = FirebaseFirestore.instance;
    final cs = await db
        .collection('clients')
        .where('companyId', isEqualTo: widget.companyId)
        .get();
    final ws = await db
        .collection('users')
        .where('companyId', isEqualTo: widget.companyId)
        .get();
    if (!mounted) return;
    setState(() {
      _clients = cs.docs
          .map((d) => {
                'id': d.id,
                ...Map<String, dynamic>.from(d.data() as Map)
              })
          .toList();
      _workers = ws.docs
          .map((d) => Map<String, dynamic>.from(d.data() as Map))
          .where((u) => u['role'] != 'admin')
          .toList();
    });
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (d != null && mounted) setState(() => _date = d);
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ponle un título al trabajo.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final db = FirebaseFirestore.instance;
      final Map<String, dynamic> data = {
        'companyId': widget.companyId,
        'clientId': _clientId,
        'clientName': _clientName,
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'address': _addrCtrl.text.trim(),
        'status': _status,
        'scheduledDate':
            _date != null ? Timestamp.fromDate(_date!) : null,
        'assignedTo': _assignedTo,
        'assignedName': _assignedName,
        'price': double.tryParse(_priceCtrl.text.trim()) ?? 0,
        'notes': _notesCtrl.text.trim(),
      };
      if (widget.job == null) {
        data['createdAt'] = FieldValue.serverTimestamp();
        await db.collection('jobs').add(data);
      } else {
        await db
            .collection('jobs')
            .doc(widget.job!.id)
            .update(data);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(
              widget.job == null ? 'Nuevo trabajo' : 'Editar trabajo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: 'Título *',
              hintText: 'Ej: Reparación de drywall',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _clientId.isEmpty ? null : _clientId,
            decoration: const InputDecoration(
              labelText: 'Cliente',
              border: OutlineInputBorder(),
            ),
            items: _clients
                .map((c) => DropdownMenuItem<String>(
                      value: c['id'] as String,
                      child: Text(c['name'] as String? ?? ''),
                    ))
                .toList(),
            onChanged: (v) {
              final c = _clients.firstWhere((x) => x['id'] == v,
                  orElse: () => <String, dynamic>{});
              setState(() {
                _clientId = v ?? '';
                _clientName = c['name'] as String? ?? '';
                if (_addrCtrl.text.isEmpty) {
                  _addrCtrl.text = c['address'] as String? ?? '';
                }
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Descripción',
              hintText: 'Qué hay que hacer...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addrCtrl,
            decoration: const InputDecoration(
              labelText: 'Dirección',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today),
                  label: Text(fmtDate(_date)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                          decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Precio \$',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _assignedTo.isEmpty ? null : _assignedTo,
            decoration: const InputDecoration(
              labelText: 'Asignar a',
              border: OutlineInputBorder(),
            ),
            items: _workers
                .map((w) => DropdownMenuItem<String>(
                      value: w['uid'] as String? ?? '',
                      child:
                          Text(w['displayName'] as String? ?? ''),
                    ))
                .toList(),
            onChanged: (v) {
              final w = _workers.firstWhere(
                  (x) => x['uid'] == v,
                  orElse: () => <String, dynamic>{});
              setState(() {
                _assignedTo = v ?? '';
                _assignedName =
                    w['displayName'] as String? ?? '';
              });
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _status,
            decoration: const InputDecoration(
              labelText: 'Estado',
              border: OutlineInputBorder(),
            ),
            items: kJobStatus.entries
                .map((e) => DropdownMenuItem<String>(
                      value: e.key,
                      child: Text(e.value),
                    ))
                .toList(),
            onChanged: (v) =>
                setState(() => _status = v ?? 'pendiente'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Notas internas',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(vertical: 16)),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 3))
                : Text(widget.job == null
                    ? 'Crear trabajo'
                    : 'Guardar cambios'),
          ),
        ],
      ),
    );
  }
}

class JobDetailScreen extends StatefulWidget {
  final Job job;
  final bool isAdmin;
  const JobDetailScreen(
      {super.key, required this.job, required this.isAdmin});
  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  late String _status;

  @override
  void initState() {
    super.initState();
    _status = widget.job.status;
  }

  Future<void> _setStatus(String st) async {
    setState(() => _status = st);
    await FirebaseFirestore.instance
        .collection('jobs')
        .doc(widget.job.id)
        .update({'status': st});
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eliminar trabajo'),
        content: Text('¿Eliminar "${widget.job.title}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await FirebaseFirestore.instance
          .collection('jobs')
          .doc(widget.job.id)
          .delete();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.job;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del trabajo'),
        actions: [
          if (widget.isAdmin)
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => JobFormScreen(
                    companyId: j.companyId,
                    job: j,
                  ),
                ),
              ).then((_) => Navigator.pop(context)),
            ),
          if (widget.isAdmin)
            IconButton(
              tooltip: 'Eliminar',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(j.title,
              style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              Chip(label: Text(kJobStatus[_status] ?? '')),
              if (j.price > 0)
                Chip(
                    label: Text(
                        '\$${j.price.toStringAsFixed(0)}')),
            ],
          ),
          const SizedBox(height: 16),
          _row('👤 Cliente',
              j.clientName.isEmpty ? '—' : j.clientName),
          _row('📍 Dirección',
              j.address.isEmpty ? '—' : j.address),
          _row('📅 Fecha', fmtDate(j.scheduledDate)),
          _row('👷 Asignado a',
              j.assignedName.isEmpty ? 'Sin asignar' : j.assignedName),
          if (j.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Descripción',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(j.description),
          ],
          if (j.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Notas internas',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(j.notes),
          ],
          const SizedBox(height: 24),
          const Text('Cambiar estado',
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: kJobStatus.entries
                .map((e) => ChoiceChip(
                      label: Text(e.value),
                      selected: _status == e.key,
                      onSelected: (_) => _setStatus(e.key),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 130,
              child: Text(label,
                  style: const TextStyle(color: Colors.grey))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}

// ==================== FASE 2: CLIENTES ====================

class ClientsScreen extends StatelessWidget {
  final String companyId;
  final bool isAdmin;
  const ClientsScreen(
      {super.key, required this.companyId, required this.isAdmin});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('clients')
            .where('companyId', isEqualTo: companyId)
            .orderBy('name')
            .snapshots(),
        builder: (c, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator());
          }
          final clients = snap.data!.docs
              .map((d) => Client.fromMap(d.id,
                  Map<String, dynamic>.from(d.data() as Map)))
              .toList();
          if (clients.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Sin clientes todavía.\nAgrégalos con el botón ＋.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: clients.length,
            itemBuilder: (c, i) {
              final cl = clients[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                      child: Text(cl.name.isNotEmpty
                          ? cl.name
                              .substring(0, 1)
                              .toUpperCase()
                          : '?')),
                  title: Text(cl.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold)),
                  subtitle: Text(
                      [cl.phone, cl.address]
                          .where((x) => x.isNotEmpty)
                          .join(' · '),
                      maxLines: 1),
                  trailing:
                      const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ClientDetailScreen(
                        client: cl,
                        isAdmin: isAdmin,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ClientFormScreen(
                    companyId: companyId,
                  ),
                ),
              ),
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class ClientFormScreen extends StatefulWidget {
  final String companyId;
  final Client? client;
  const ClientFormScreen(
      {super.key, required this.companyId, this.client});
  @override
  State<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends State<ClientFormScreen> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addrCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.client;
    if (c != null) {
      _nameCtrl.text = c.name;
      _phoneCtrl.text = c.phone;
      _emailCtrl.text = c.email;
      _addrCtrl.text = c.address;
      _notesCtrl.text = c.notes;
    }
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('El nombre es obligatorio.')));
      return;
    }
    setState(() => _saving = true);
    try {
      final db = FirebaseFirestore.instance;
      final Map<String, dynamic> data = {
        'companyId': widget.companyId,
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'address': _addrCtrl.text.trim(),
        'notes': _notesCtrl.text.trim(),
      };
      if (widget.client == null) {
        data['createdAt'] = FieldValue.serverTimestamp();
        await db.collection('clients').add(data);
      } else {
        await db
            .collection('clients')
            .doc(widget.client!.id)
            .update(data);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.client == null
              ? 'Nuevo cliente'
              : 'Editar cliente')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Teléfono',
                  border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Correo',
                  border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(
              controller: _addrCtrl,
              decoration: const InputDecoration(
                  labelText: 'Dirección',
                  border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(
              controller: _notesCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                  labelText: 'Notas',
                  border: OutlineInputBorder())),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(vertical: 16)),
            onPressed: _saving ? null : _save,
            child: Text(widget.client == null
                ? 'Crear cliente'
                : 'Guardar cambios'),
          ),
        ],
      ),
    );
  }
}

class ClientDetailScreen extends StatelessWidget {
  final Client client;
  final bool isAdmin;
  const ClientDetailScreen(
      {super.key, required this.client, required this.isAdmin});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cliente'),
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ClientFormScreen(
                    companyId: client.companyId,
                    client: client,
                  ),
                ),
              ).then((_) => Navigator.pop(context)),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: CircleAvatar(
              radius: 36,
              child: Text(
                  client.name.isNotEmpty
                      ? client.name.substring(0, 1).toUpperCase()
                      : '?',
                  style: const TextStyle(fontSize: 28)),
            ),
          ),
          const SizedBox(height: 12),
          Center(
              child: Text(client.name,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold))),
          const SizedBox(height: 20),
          if (client.phone.isNotEmpty)
            ListTile(
                leading: const Icon(Icons.phone),
                title: Text(client.phone)),
          if (client.email.isNotEmpty)
            ListTile(
                leading: const Icon(Icons.email),
                title: Text(client.email)),
          if (client.address.isNotEmpty)
            ListTile(
                leading: const Icon(Icons.location_on),
                title: Text(client.address)),
          if (client.notes.isNotEmpty)
            ListTile(
                leading: const Icon(Icons.note),
                title: Text(client.notes)),
          const SizedBox(height: 12),
          const Text('Trabajos de este cliente',
              style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('jobs')
                .where('companyId',
                    isEqualTo: client.companyId)
                .where('clientId', isEqualTo: client.id)
                .snapshots(),
            builder: (c, snap) {
              if (!snap.hasData) {
                return const Center(
                    child: CircularProgressIndicator());
              }
              final jobs = snap.data!.docs
                  .map((d) => Job.fromMap(
                      d.id,
                      Map<String, dynamic>.from(
                          d.data() as Map)))
                  .toList();
              if (jobs.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Sin trabajos todavía.',
                      style: TextStyle(color: Colors.grey)),
                );
              }
              return Column(
                children: jobs
                    .map((j) => Card(
                          child: ListTile(
                            title: Text(j.title),
                            subtitle: Text(
                                '${kJobStatus[j.status] ?? ""} · ${fmtDate(j.scheduledDate)}'),
                            trailing: const Icon(
                                Icons.chevron_right),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    JobDetailScreen(
                                  job: j,
                                  isAdmin: isAdmin,
                                ),
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ==================== FASE 2: CALENDARIO ====================

class CalendarScreen extends StatefulWidget {
  final String companyId;
  final bool isAdmin;
  final String uid;
  const CalendarScreen(
      {super.key,
      required this.companyId,
      required this.isAdmin,
      required this.uid});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month;
  DateTime? _selDay;
  List<Job> _jobs = [];

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month);
    _selDay = DateTime(n.year, n.month, n.day);
    _load();
  }

  Future<void> _load() async {
    Query q = FirebaseFirestore.instance
        .collection('jobs')
        .where('companyId', isEqualTo: widget.companyId);
    if (!widget.isAdmin) {
      q = q.where('assignedTo', isEqualTo: widget.uid);
    }
    final snap = await q.get();
    if (!mounted) return;
    setState(() {
      _jobs = snap.docs
          .map((d) => Job.fromMap(
              d.id,
              Map<String, dynamic>.from(
                  d.data() as Map)))
          .where((j) => j.scheduledDate != null)
          .toList();
    });
  }

  List<Job> _jobsOf(DateTime day) {
    return _jobs
        .where((j) =>
            j.scheduledDate!.year == day.year &&
            j.scheduledDate!.month == day.month &&
            j.scheduledDate!.day == day.day)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    const ms = [
      'Enero','Febrero','Marzo','Abril','Mayo','Junio',
      'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'
    ];
    final first = DateTime(_month.year, _month.month, 1);
    final startOffset = first.weekday % 7; // domingo = 0
    final daysInMonth =
        DateTime(_month.year, _month.month + 1, 0).day;
    final today = DateTime.now();
    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(() {
                  _month =
                      DateTime(_month.year, _month.month - 1);
                }),
              ),
              Text('${ms[_month.month - 1]} ${_month.year}',
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(() {
                  _month =
                      DateTime(_month.year, _month.month + 1);
                }),
              ),
            ],
          ),
        ),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: const ['D','L','M','X','J','V','S']
                .map((d) => Expanded(
                        child: Center(
                            child: Text(d,
                                style: const TextStyle(
                                    color: Colors.grey,
                                    fontWeight:
                                        FontWeight.bold)))))
                .toList(),
          ),
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding:
              const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7),
          itemCount: startOffset + daysInMonth,
          itemBuilder: (c, i) {
            if (i < startOffset) {
              return const SizedBox.shrink();
            }
            final day = i - startOffset + 1;
            final d =
                DateTime(_month.year, _month.month, day);
            final has = _jobsOf(d).isNotEmpty;
            final isSel = _selDay != null &&
                _selDay!.year == d.year &&
                _selDay!.month == d.month &&
                _selDay!.day == d.day;
            final isToday = today.year == d.year &&
                today.month == d.month &&
                today.day == d.day;
            return InkWell(
              onTap: () =>
                  setState(() => _selDay = d),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isSel
                      ? const Color(0xFF1565C0)
                      : isToday
                          ? const Color(0xFF1565C0)
                              .withOpacity(0.15)
                          : null,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  children: [
                    Text('$day',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isSel
                                ? Colors.white
                                : null)),
                    if (has)
                      Container(
                        width: 6,
                        height: 6,
                        margin:
                            const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSel
                              ? Colors.white
                              : const Color(0xFF1565C0),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const Divider(height: 24),
        Expanded(
          child: _selDay == null
              ? const Center(
                  child: Text('Toca un día.',
                      style:
                          TextStyle(color: Colors.grey)))
              : _dayList(),
        ),
      ],
    );
  }

  Widget _dayList() {
    final jobs = _jobsOf(_selDay!);
    if (jobs.isEmpty) {
      return Center(
        child: Text(
          'Sin trabajos el ${fmtDate(_selDay)}.',
          style:
              const TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: jobs.length,
      itemBuilder: (c, i) {
        final j = jobs[i];
        return Card(
          child: ListTile(
            title: Text(j.title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold)),
            subtitle: Text(
                '${kJobStatus[j.status] ?? ""}${j.clientName.isNotEmpty ? " · " + j.clientName : ""}'),
            trailing:
                const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => JobDetailScreen(
                  job: j,
                  isAdmin: widget.isAdmin,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

