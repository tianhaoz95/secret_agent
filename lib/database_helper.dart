import 'dart:async';
import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'models.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;

  static Database? _database;

  DatabaseHelper._internal();

  Future<void> init() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'secret_agent_data.db');
    return await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE messages(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        agent_id INTEGER,
        text TEXT,
        is_user INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE agents(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        model_name TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE models(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        url TEXT,
        filename TEXT,
        type TEXT
      )
    ''');
    await _populateDefaultModels(db);
  }

  Future<void> _populateDefaultModels(Database db) async {
    for (var entry in defaultModelUrls.entries) {
      await db.insert('models', {'name': entry.key, 'url': entry.value, 'filename': null, 'type': 'LM'});
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE models ADD COLUMN filename TEXT;');
      await db.execute('ALTER TABLE models ADD COLUMN type TEXT;');
    }
  }

  Future<int> insertMessage(int agentId, String message, bool isUser) async {
    final db = await database;
    return await db.insert('messages', {
      'agent_id': agentId,
      'text': message,
      'is_user': isUser ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getMessages(int agentId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'messages',
      where: 'agent_id = ?',
      whereArgs: [agentId],
    );
    return maps;
  }

  Future<void> clearMessages(int agentId) async {
    final db = await database;
    await db.delete('messages', where: 'agent_id = ?', whereArgs: [agentId]);
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('messages');
    await db.delete('agents');
    await db.delete('models');
  }

  // Agent related methods
  Future<int> insertAgent(Map<String, dynamic> agent) async {
    final db = await database;
    return await db.insert(
      'agents',
      agent,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAgents() async {
    final db = await database;
    return await db.query('agents');
  }

  Future<int> updateAgent(Map<String, dynamic> agent) async {
    final db = await database;
    return await db.update(
      'agents',
      agent,
      where: 'id = ?',
      whereArgs: [agent['id']],
    );
  }

  Future<int> deleteAgent(int id) async {
    final db = await database;
    return await db.delete('agents', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAgents() async {
    final db = await database;
    await db.delete('agents');
  }

  Future<List<Map<String, dynamic>>> getModels() async {
    final db = await database;
    return await db.query('models');
  }

  Future<int> insertModel(Map<String, dynamic> model) async {
    final db = await database;
    return await db.insert(
      'models',
      model,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> updateModel(Map<String, dynamic> model) async {
    final db = await database;
    return await db.update(
      'models',
      model,
      where: 'id = ?',
      whereArgs: [model['id']],
    );
  }

  Future<int> deleteModel(int id) async {
    final db = await database;
    return await db.delete('models', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<String>> getDistinctModelNames() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'models',
      distinct: true,
      columns: ['name'],
    );
    return maps.map((map) => map['name'] as String).toList();
  }
}
