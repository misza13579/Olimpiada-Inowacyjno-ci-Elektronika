import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

// --- KONFIGURACJA UUID ---
const String SERVICE_UUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
const String CHARACTERISTIC_UUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BleController()),
        ChangeNotifierProvider(create: (_) => GameController()),
      ],
      child: const ChessApp(),
    ),
  );
}

// --- STYLIZACJA ---
class AppColors {
  static const brownDark = Color(0xFF3E2723);
  static const brownMedium = Color(0xFF5D4037);
  static const beigeLight = Color(0xFFF5F5DC);
  static const beigeMedium = Color(0xFFD7CCC8);
  static const accentGold = Color(0xFFC6A664);
}

// --- LOGIKA BLUETOOTH ---
class BleController extends ChangeNotifier {
  BluetoothDevice? connectedDevice;
  BluetoothCharacteristic? txRxChar;
  List<ScanResult> scanResults = [];
  bool isScanning = false;
  StreamSubscription? _notifySubscription;

  Future<void> startScan() async {
    isScanning = true;
    scanResults = [];
    notifyListeners();
    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
      FlutterBluePlus.scanResults.listen((results) {
        scanResults = results;
        notifyListeners();
      });
    } catch (e) {
      debugPrint("Błąd: $e");
    }
    await Future.delayed(const Duration(seconds: 4));
    isScanning = false;
    notifyListeners();
  }

  Future<bool> connect(
    BluetoothDevice device,
    Function(String) onDataReceived,
  ) async {
    try {
      await device
          .connect(autoConnect: false, license: License.free)
          .timeout(const Duration(seconds: 10));

      connectedDevice = device;
      List<BluetoothService> services = await device.discoverServices();
      for (var s in services) {
        if (s.uuid.toString().toLowerCase() == SERVICE_UUID.toLowerCase()) {
          for (var c in s.characteristics) {
            if (c.uuid.toString().toLowerCase() ==
                CHARACTERISTIC_UUID.toLowerCase()) {
              txRxChar = c;
              await c.setNotifyValue(true);
              _notifySubscription = c.lastValueStream.listen((value) {
                if (value.isNotEmpty) onDataReceived(utf8.decode(value));
              });
              sendData("PING");
              notifyListeners();
              return true;
            }
          }
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  void sendData(String data) {
    if (txRxChar != null) txRxChar!.write(utf8.encode(data));
  }

  void disconnect() {
    _notifySubscription?.cancel();
    connectedDevice?.disconnect();
    connectedDevice = null;
    txRxChar = null;
    notifyListeners();
  }
}

// --- LOGIKA GRY I ARCHIWUM ---
class GameController extends ChangeNotifier {
  List<String> moves = [];
  List<Map<String, dynamic>> archive = [];
  double difficulty = 800;
  double gameTime = 10;
  bool isConnecting = false;

  void setConnecting(bool val) {
    isConnecting = val;
    notifyListeners();
  }

  void updateDifficulty(double val) {
    difficulty = val;
    notifyListeners();
  }

  void updateTime(double val) {
    gameTime = val;
    notifyListeners();
  }

  void handleIncomingData(String msg) {
    if (msg == "PONG") return;
    moves.add(msg);
    notifyListeners();
  }

  void startNewGame(BleController ble) {
    moves.clear();
    ble.sendData(
      "START_GAME:ELO:${difficulty.toInt()}:TIME:${gameTime.toInt()}",
    );
    notifyListeners();
  }

  void saveGame() {
    if (moves.isNotEmpty) {
      archive.insert(0, {
        'date': DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now()),
        'elo': difficulty.toInt(),
        'time': gameTime.toInt(),
        'moves': List.from(moves),
      });
      moves.clear();
      notifyListeners();
    }
  }
}

// --- UI ---
class ChessApp extends StatelessWidget {
  const ChessApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.beigeLight,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.brownDark,
          foregroundColor: Colors.white,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  final List<Widget> _screens = [
    const ConnectTab(),
    const GameTab(),
    const ArchiveTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        backgroundColor: AppColors.brownDark,
        selectedItemColor: AppColors.accentGold,
        unselectedItemColor: AppColors.beigeMedium,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.bluetooth), label: "Link"),
          BottomNavigationBarItem(
            icon: Icon(Icons.play_circle_fill),
            label: "Gra",
          ),
          BottomNavigationBarItem(icon: Icon(Icons.folder), label: "Zapisy"),
        ],
      ),
    );
  }
}

class ConnectTab extends StatelessWidget {
  const ConnectTab({super.key});
  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleController>();
    final game = context.watch<GameController>();

    return Column(
      children: [
        const SizedBox(height: 80),
        game.isConnecting
            ? const SizedBox(
                height: 80,
                width: 80,
                child: CircularProgressIndicator(
                  color: AppColors.brownDark,
                  strokeWidth: 5,
                ),
              )
            : const Icon(
                Icons.bluetooth_audio,
                size: 80,
                color: AppColors.brownDark,
              ),
        const SizedBox(height: 20),
        Text(
          game.isConnecting
              ? "Łączenie..."
              : (ble.connectedDevice == null ? "Rozłączono" : "Połączono"),
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.brownDark,
          ),
        ),
        const SizedBox(height: 30),
        if (ble.connectedDevice == null)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brownMedium,
            ),
            onPressed: ble.isScanning ? null : ble.startScan,
            child: Text(
              ble.isScanning ? "Szukam..." : "Skanuj",
              style: const TextStyle(color: Colors.white),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: ble.scanResults.length,
            itemBuilder: (context, i) {
              final d = ble.scanResults[i].device;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                color: AppColors.beigeMedium,
                child: ListTile(
                  title: Text(
                    d.platformName.isEmpty ? "Urządzenie BLE" : d.platformName,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    game.setConnecting(true);
                    await ble.connect(d, game.handleIncomingData);
                    game.setConnecting(false);
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class GameTab extends StatelessWidget {
  const GameTab({super.key});
  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleController>();
    final game = context.watch<GameController>();

    if (ble.connectedDevice == null)
      return const Center(
        child: Text(
          "Połącz Bluetooth",
          style: TextStyle(color: AppColors.brownDark),
        ),
      );

    return Column(
      children: [
        const SizedBox(height: 50),
        Container(
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: AppColors.brownDark,
            borderRadius: BorderRadius.circular(15),
          ),
          child: Column(
            children: [
              Text(
                "ELO: ${game.difficulty.toInt()}",
                style: const TextStyle(
                  color: AppColors.accentGold,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Slider(
                value: game.difficulty,
                min: 400,
                max: 2000,
                divisions: 16,
                activeColor: AppColors.accentGold,
                onChanged: (v) => game.updateDifficulty(v),
              ),
              const SizedBox(height: 10),
              Text(
                "CZAS: ${game.gameTime.toInt()} MIN",
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              Slider(
                value: game.gameTime,
                min: 1,
                max: 60,
                divisions: 59,
                activeColor: Colors.white70,
                onChanged: (v) => game.updateTime(v),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: () => game.startNewGame(ble),
                    child: const Text("START"),
                  ),
                  if (game.moves.isNotEmpty)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[900],
                      ),
                      onPressed: game.saveGame,
                      child: const Text("ZAPISZ"),
                    ),
                ],
              ),
            ],
          ),
        ),
        const Text("RUCHY:", style: TextStyle(fontWeight: FontWeight.bold)),
        Expanded(
          child: ListView.builder(
            itemCount: game.moves.length,
            itemBuilder: (context, i) => ListTile(
              leading: Text(
                "${i + 1}.",
                style: const TextStyle(
                  color: AppColors.brownMedium,
                  fontWeight: FontWeight.bold,
                ),
              ),
              title: Text(game.moves[i], style: const TextStyle(fontSize: 18)),
            ),
          ),
        ),
      ],
    );
  }
}

class ArchiveTab extends StatelessWidget {
  const ArchiveTab({super.key});
  @override
  Widget build(BuildContext context) {
    final archive = context.watch<GameController>().archive;
    return Scaffold(
      appBar: AppBar(title: const Text("Moje Partie")),
      body: archive.isEmpty
          ? const Center(child: Text("Brak zapisów"))
          : ListView.builder(
              itemCount: archive.length,
              itemBuilder: (context, i) {
                final item = archive[i];
                return Card(
                  color: AppColors.beigeMedium,
                  margin: const EdgeInsets.all(8),
                  child: ExpansionTile(
                    title: Text(
                      "${item['date']} (ELO: ${item['elo']}, ${item['time']}min)",
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(item['moves'].join(" | ")),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
