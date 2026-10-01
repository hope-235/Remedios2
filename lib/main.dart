import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

// ─── GLOBAL NOTIFICATION PLUGIN ─────────────────────────────────────────────
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// ─── BACKGROUND HANDLER ─────────────────────────────────────────────────────
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (notificationResponse.payload != null) {
    final prefs = await SharedPreferences.getInstance();
    final String actionId = notificationResponse.actionId ?? '';
    final String payload = notificationResponse.payload!;

    if (actionId == 'taken') {
      List<String> remediosJson = prefs.getStringList('remedios') ?? [];
      for (int i = 0; i < remediosJson.length; i++) {
        Map<String, dynamic> r = jsonDecode(remediosJson[i]);
        if (r['id'] == payload) {
          int inv = r['inventory'] ?? 0;
          if (inv > 0) {
            r['inventory'] = inv - 1;
            remediosJson[i] = jsonEncode(r);
            await prefs.setStringList('remedios', remediosJson);
          }
          break;
        }
      }
    }
  }
}

// ─── ENTRY POINT ────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  runApp(const RemediosRingApp());
}

// ─── APP ROOT ───────────────────────────────────────────────────────────────
class RemediosRingApp extends StatelessWidget {
  const RemediosRingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RemediosRing',
      theme: _buildLightTheme(),
      darkTheme: _buildDarkTheme(),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }

  ThemeData _buildLightTheme() {
    const seed = Color(0xFF00796B);
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.light);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: scheme.onPrimary,
          letterSpacing: 1.1,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      cardTheme: CardTheme(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    const seed = Color(0xFF00796B);
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
          letterSpacing: 1.1,
        ),
      ),
      cardTheme: CardTheme(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

// ─── HOME PAGE ──────────────────────────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  List<Map<String, dynamic>> remedios = [];
  late SharedPreferences prefs;
  late AnimationController _fabController;

  // ── lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _fabController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
    _initNotifications();
    _loadData();
  }

  @override
  void dispose() {
    _fabController.dispose();
    super.dispose();
  }

  // ── notifications ─────────────────────────────────────────────────────────
  Future<void> _initNotifications() async {
    const AndroidInitializationSettings initAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: initAndroid);

    await flutterLocalNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        if (details.actionId == 'snooze' && details.payload != null) {
          _snoozeRemedio(details.payload!);
        } else if (details.actionId == 'taken' && details.payload != null) {
          _markTaken(details.payload!);
        }
        _loadData();
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }
    if (await Permission.scheduleExactAlarm.isDenied) {
      await Permission.scheduleExactAlarm.request();
    }
  }

  // ── persistence ────────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    prefs = await SharedPreferences.getInstance();
    final List<String> raw = prefs.getStringList('remedios') ?? [];
    setState(() {
      remedios = raw.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
    });
  }

  Future<void> _saveData() async {
    final List<String> raw = remedios.map((r) => jsonEncode(r)).toList();
    await prefs.setStringList('remedios', raw);
  }

  // ── snooze / mark taken ───────────────────────────────────────────────────
  void _snoozeRemedio(String id) async {
    final target = remedios.firstWhere((r) => r['id'] == id, orElse: () => {});
    if (target.isEmpty) return;

    final snoozeTime = DateTime.now().add(const Duration(minutes: 10));

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'remedios_channel',
      'Remedios',
      channelDescription: 'Notificaciones de Remedios',
      importance: Importance.max,
      priority: Priority.high,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('taken', '✅ Ya lo tomé'),
        AndroidNotificationAction('snooze', '⏰ Posponer 10 min'),
      ],
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.zonedSchedule(
      (id + 'snooze').hashCode,
      '⏰ Pospuesto: ${target['name']}',
      'Ahora sí, ¡es hora de tomar ${target['dosis']}!',
      tz.TZDateTime.from(snoozeTime, tz.local),
      details,
      payload: id,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  void _markTaken(String id) {
    setState(() {
      for (var r in remedios) {
        if (r['id'] == id) {
          int inv = r['inventory'] ?? 0;
          if (inv > 0) r['inventory'] = inv - 1;
          break;
        }
      }
    });
    _saveData();
  }

  // ── schedule all notifications for a remedio ──────────────────────────────
  Future<void> _scheduleNotifications(Map<String, dynamic> remedio) async {
    final int interval = remedio['interval'] ?? 0;
    final int duration = remedio['duration'] ?? 1;
    final String id = remedio['id'];
    final DateTime now = DateTime.now();
    final List<String> parts = remedio['time'].split(':');
    DateTime base = DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
    if (base.isBefore(now)) base = base.add(const Duration(days: 1));

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'remedios_channel',
      'Remedios',
      channelDescription: 'Notificaciones de Remedios',
      importance: Importance.max,
      priority: Priority.high,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('taken', '✅ Ya lo tomé'),
        AndroidNotificationAction('snooze', '⏰ Posponer 10 min'),
      ],
    );
    const NotificationDetails platformDetails =
        NotificationDetails(android: androidDetails);

    final int maxSlots = interval > 0 ? (24 ~/ interval) * duration : 1;

    for (int i = 0; i < maxSlots; i++) {
      final DateTime target = base.add(Duration(hours: interval * i));
      final DateTime before = target.subtract(const Duration(minutes: 2));
      final DateTime after = target.add(const Duration(minutes: 2));
      final int baseHash = (id + i.toString()).hashCode;

      if (before.isAfter(now)) {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          baseHash,
          '⏳ Prepárate: ${remedio['name']}',
          'En 2 minutos debes tomar ${remedio['dosis']}',
          tz.TZDateTime.from(before, tz.local),
          platformDetails,
          payload: id,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }

      if (after.isAfter(now)) {
        await flutterLocalNotificationsPlugin.zonedSchedule(
          baseHash + 1,
          '🔔 Recordatorio: ${remedio['name']}',
          '¿Ya tomaste ${remedio['dosis']}? Pasaron 2 min de la hora.',
          tz.TZDateTime.from(after, tz.local),
          platformDetails,
          payload: id,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }
  }

  // ── helpers ────────────────────────────────────────────────────────────────
  IconData _iconFor(String type) {
    switch (type) {
      case 'Pastilla':
        return Icons.medication_rounded;
      case 'Jarabe':
        return Icons.local_drink_rounded;
      case 'Gotas':
        return Icons.water_drop_rounded;
      case 'Inyección':
        return Icons.vaccines_rounded;
      default:
        return Icons.medical_services_rounded;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'Pastilla':
        return const Color(0xFF1565C0);
      case 'Jarabe':
        return const Color(0xFFE65100);
      case 'Gotas':
        return const Color(0xFF00695C);
      case 'Inyección':
        return const Color(0xFFC62828);
      default:
        return Colors.grey;
    }
  }

  String _formatTime(String raw) {
    final p = raw.split(':');
    final h = int.parse(p[0]);
    final m = int.parse(p[1]);
    final period = h >= 12 ? 'PM' : 'AM';
    final hh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '${hh.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')} $period';
  }

  // ── delete remedio ─────────────────────────────────────────────────────────
  void _deleteRemedio(int index) {
    final name = remedios[index]['name'];
    setState(() => remedios.removeAt(index));
    _saveData();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('"$name" eliminado')),
    );
  }

  // ── add dialog ─────────────────────────────────────────────────────────────
  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final dosisCtrl = TextEditingController();
    final inventoryCtrl = TextEditingController();
    TimeOfDay selectedTime = TimeOfDay.now();
    String selectedType = 'Pastilla';
    int interval = 0;
    int duration = 1;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Header
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[400],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Nuevo Remedio',
                      style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // ── Tipo (chips)
                    const Text('Tipo de remedio',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ['Pastilla', 'Jarabe', 'Gotas', 'Inyección']
                          .map((t) => ChoiceChip(
                                avatar: Icon(_iconFor(t), size: 18),
                                label: Text(t),
                                selected: selectedType == t,
                                selectedColor:
                                    _colorFor(t).withOpacity(0.25),
                                onSelected: (_) =>
                                    setSheetState(() => selectedType = t),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 16),

                    // ── Nombre
                    TextField(
                      controller: nameCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'Nombre del remedio',
                        prefixIcon: Icon(_iconFor(selectedType)),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Dosis
                    TextField(
                      controller: dosisCtrl,
                      decoration: InputDecoration(
                        labelText: 'Dosis (ej. 1 pastilla, 10 ml)',
                        prefixIcon: const Icon(Icons.science_rounded),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Inventario
                    TextField(
                      controller: inventoryCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Cantidad total (opcional)',
                        prefixIcon: const Icon(Icons.inventory_2_rounded),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14)),
                        helperText: 'Te avisamos cuando queden pocas',
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Hora
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        final t = await showTimePicker(
                          context: ctx,
                          initialTime: selectedTime,
                        );
                        if (t != null) setSheetState(() => selectedTime = t);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time_rounded),
                            const SizedBox(width: 12),
                            Text(
                              'Hora: ${selectedTime.format(ctx)}',
                              style: const TextStyle(fontSize: 16),
                            ),
                            const Spacer(),
                            Text('Cambiar',
                                style: TextStyle(
                                    color:
                                        Theme.of(ctx).colorScheme.primary,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Frecuencia
                    Row(
                      children: [
                        const Icon(Icons.repeat_rounded, size: 20),
                        const SizedBox(width: 8),
                        const Text('Frecuencia:',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: interval,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                            items: [0, 4, 6, 8, 12, 24]
                                .map((i) => DropdownMenuItem(
                                      value: i,
                                      child: Text(i == 0
                                          ? 'Una sola vez'
                                          : 'Cada $i horas'),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setSheetState(() => interval = v!),
                          ),
                        ),
                      ],
                    ),
                    if (interval > 0) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 20),
                          const SizedBox(width: 8),
                          const Text('Duración:',
                              style:
                                  TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: duration,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14)),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              items: [1, 2, 3, 5, 7, 10, 14, 30]
                                  .map((d) => DropdownMenuItem(
                                        value: d,
                                        child: Text('$d días'),
                                      ))
                                  .toList(),
                              onChanged: (v) =>
                                  setSheetState(() => duration = v!),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),

                    // ── Botón guardar
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Guardar Remedio',
                          style: TextStyle(fontSize: 16)),
                      onPressed: () {
                        if (nameCtrl.text.trim().isEmpty ||
                            dosisCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Completa el nombre y la dosis')),
                          );
                          return;
                        }
                        final newRemedio = {
                          'id': const Uuid().v4(),
                          'name': nameCtrl.text.trim(),
                          'type': selectedType,
                          'dosis': dosisCtrl.text.trim(),
                          'inventory':
                              int.tryParse(inventoryCtrl.text) ?? 0,
                          'time':
                              '${selectedTime.hour}:${selectedTime.minute}',
                          'interval': interval,
                          'duration': duration,
                        };
                        setState(() => remedios.add(newRemedio));
                        _saveData();
                        _scheduleNotifications(newRemedio);
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  '"${newRemedio['name']}" programado ✅')),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.health_and_safety_rounded,
                color: cs.onPrimary, size: 28),
            const SizedBox(width: 8),
            const Text('RemediosRing'),
          ],
        ),
      ),
      body: remedios.isEmpty ? _buildEmptyState(cs) : _buildList(cs),
      floatingActionButton: ScaleTransition(
        scale: CurvedAnimation(
            parent: _fabController, curve: Curves.easeOutBack),
        child: FloatingActionButton.extended(
          onPressed: _showAddDialog,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Nuevo Remedio',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.health_and_safety_rounded,
                size: 100, color: cs.primary.withOpacity(0.3)),
            const SizedBox(height: 24),
            Text(
              'Sin remedios programados',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Toca el botón de abajo para agregar\ntu primer remedio',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurface.withOpacity(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(ColorScheme cs) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 12, bottom: 100),
      itemCount: remedios.length,
      itemBuilder: (context, index) {
        final r = remedios[index];
        final String type = r['type'] ?? 'Otro';
        final int inv = r['inventory'] ?? 0;
        final bool lowStock = inv > 0 && inv <= 3;
        final Color typeColor = _colorFor(type);

        return Dismissible(
          key: Key(r['id']),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red[400],
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.delete_rounded,
                color: Colors.white, size: 28),
          ),
          confirmDismiss: (_) async {
            return await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Eliminar remedio'),
                content: Text('¿Eliminar "${r['name']}"?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Eliminar')),
                ],
              ),
            );
          },
          onDismissed: (_) => _deleteRemedio(index),
          child: Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {},
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    // ── Icon
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: typeColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(_iconFor(type),
                          color: typeColor, size: 28),
                    ),
                    const SizedBox(width: 14),

                    // ── Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r['name'],
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 17)),
                          const SizedBox(height: 4),
                          Text('${r['dosis']}  ·  $type',
                              style: TextStyle(
                                  color: cs.onSurface.withOpacity(0.6),
                                  fontSize: 13)),
                          if ((r['interval'] ?? 0) > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Cada ${r['interval']}h por ${r['duration']} días',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: cs.primary,
                                    fontWeight: FontWeight.w500),
                              ),
                            ),
                          if (inv > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                children: [
                                  Icon(
                                    lowStock
                                        ? Icons.warning_rounded
                                        : Icons.inventory_2_rounded,
                                    size: 14,
                                    color:
                                        lowStock ? Colors.red : Colors.green,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    lowStock
                                        ? '¡Quedan solo $inv!'
                                        : 'Quedan: $inv',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: lowStock
                                          ? Colors.red
                                          : Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),

                    // ── Time badge + check
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: cs.secondaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _formatTime(r['time']),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: cs.onSecondaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            _markTaken(r['id']);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      '${r['name']} marcado como tomado ✅')),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check_rounded,
                                color: Colors.green, size: 22),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
