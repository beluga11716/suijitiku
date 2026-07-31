import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'randomselector.db');
    return await openDatabase(
      path,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE question_banks (
        id            TEXT PRIMARY KEY,
        name          TEXT NOT NULL,
        source_file   TEXT,
        source_type   TEXT,
        question_count INTEGER DEFAULT 0,
        llm_analyzed_at TEXT,
        created_at    TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE questions (
        id               TEXT PRIMARY KEY,
        bank_id          TEXT NOT NULL,
        type             TEXT NOT NULL,
        stem             TEXT NOT NULL,
        options          TEXT DEFAULT '[]',
        answer           TEXT NOT NULL,
        explanation      TEXT,
        difficulty_score REAL DEFAULT 0.0,
        importance_score REAL DEFAULT 0.0,
        theory_score     REAL DEFAULT 0.0,
        featured_score   REAL DEFAULT 0.0,
        chapter          TEXT,
        created_at       TEXT NOT NULL,
        FOREIGN KEY (bank_id) REFERENCES question_banks(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE quiz_sessions (
        id             TEXT PRIMARY KEY,
        bank_id        TEXT,
        mode           TEXT NOT NULL,
        quiz_style     TEXT NOT NULL,
        question_count INTEGER NOT NULL,
        correct_count  INTEGER DEFAULT 0,
        wrong_count    INTEGER DEFAULT 0,
        status         TEXT DEFAULT 'in_progress',
        started_at     TEXT NOT NULL,
        completed_at   TEXT,
        name           TEXT DEFAULT '',
        current_index  INTEGER DEFAULT 0,
        source         TEXT DEFAULT 'bank',
        question_types TEXT,
        question_ids   TEXT,
        FOREIGN KEY (bank_id) REFERENCES question_banks(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE quiz_answers (
        id          TEXT PRIMARY KEY,
        session_id  TEXT NOT NULL,
        question_id TEXT,
        user_answer TEXT,
        is_correct  INTEGER DEFAULT 0,
        answered_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES quiz_sessions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE wrong_questions (
        id            TEXT PRIMARY KEY,
        question_id   TEXT UNIQUE NOT NULL,
        wrong_count   INTEGER DEFAULT 1,
        last_wrong_at TEXT NOT NULL,
        created_at    TEXT NOT NULL,
        FOREIGN KEY (question_id) REFERENCES questions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Indexes
    await db.execute(
        'CREATE INDEX idx_questions_bank ON questions(bank_id)');
    await db.execute(
        'CREATE INDEX idx_answers_session ON quiz_answers(session_id)');
    await db.execute(
        'CREATE INDEX idx_wrong_question ON wrong_questions(question_id)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v1 → v2: 测试会话管理系统
      try { await db.execute("ALTER TABLE quiz_sessions ADD COLUMN name TEXT"); } catch (_) {}
      try { await db.execute("ALTER TABLE quiz_sessions ADD COLUMN current_index INTEGER DEFAULT 0"); } catch (_) {}
      try { await db.execute("ALTER TABLE quiz_sessions ADD COLUMN source TEXT DEFAULT 'bank'"); } catch (_) {}
      try { await db.execute("ALTER TABLE quiz_sessions ADD COLUMN question_types TEXT"); } catch (_) {}
      try { await db.execute("ALTER TABLE quiz_sessions ADD COLUMN question_ids TEXT"); } catch (_) {}
    }
    if (oldVersion < 3) {
      // v2 → v3: 修复 _onCreate 漏掉的列（v2 新建的库可能缺这些列）
      try { await db.execute("ALTER TABLE quiz_sessions ADD COLUMN name TEXT DEFAULT ''"); } catch (_) {}
      try { await db.execute("ALTER TABLE quiz_sessions ADD COLUMN current_index INTEGER DEFAULT 0"); } catch (_) {}
      try { await db.execute("ALTER TABLE quiz_sessions ADD COLUMN source TEXT DEFAULT 'bank'"); } catch (_) {}
      try { await db.execute("ALTER TABLE quiz_sessions ADD COLUMN question_types TEXT"); } catch (_) {}
      try { await db.execute("ALTER TABLE quiz_sessions ADD COLUMN question_ids TEXT"); } catch (_) {}
    }
    if (oldVersion < 4) {
      // v3 → v4: LLM 分析状态追踪
      try { await db.execute("ALTER TABLE question_banks ADD COLUMN llm_analyzed_at TEXT"); } catch (_) {}
    }
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
