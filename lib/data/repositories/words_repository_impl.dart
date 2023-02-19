import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:voca/data/repositories/assets_repository_impl.dart';
import 'package:voca/data/utils/pos_map.dart';
import 'package:voca/domain/entities/dictionary_entry.dart';
import 'package:voca/domain/entities/word.dart';
import 'package:voca/domain/entities/word_card.dart';
import 'package:voca/domain/entities/word_card_user_data.dart';
import 'package:voca/domain/entities/word_card_short.dart';
import 'package:voca/domain/repositories/words_repository.dart';

class _WordCardStatusText {
  static const removed = 'removed';
  static const learning = 'learning';
  static const known = 'knon';
}

const _wordStatusToText = <WordCardStatus, String>{
  WordCardStatus.learningOrLearned: _WordCardStatusText.learning,
  WordCardStatus.known: _WordCardStatusText.known,
  WordCardStatus.unknown: _WordCardStatusText.removed,
};
const _textToWordStatus = <String, WordCardStatus>{
  _WordCardStatusText.removed: WordCardStatus.unknown,
  _WordCardStatusText.learning: WordCardStatus.learningOrLearned,
  _WordCardStatusText.known: WordCardStatus.known,
};

@LazySingleton(as: WordsRepository)
class WordsRepositoryImpl implements WordsRepository {
  Database? _db;
  Future<Database> get db async {
    if (_db == null) {
      debugPrint('initializing db');

      _db = await openDatabase(
        join(await getDatabasesPath(), AssetsRepositoryImpl.enDictionaryDbName),
      );

      await _detachAllDb(_db!);
      await _attachUserProgressDb(_db!);
    }

    return _db!;
  }

  @override
  Future<List<WordCardShort>> findWords(String query) async {
    final db = await this.db;

    final qWords = await db.rawQuery('''
      SELECT rowid, word FROM word WHERE word LIKE ?
    ''', [
      '$query%',
    ]);

    final words = <WordCardShort>[];

    for (final row in qWords) {
      final word = row['word'] as String;
      final wordId = row['rowid'] as int;

      final userData = await _fetchUserWordData(wordId);

      words.add(WordCardShort(
        word: Word(name: word, id: wordId),
        userData: userData,
      ));
    }

    return words;
  }

  @override
  Future<WordCard> fetchWordCard(Word word) async {
    final db = await this.db;

    final qDefinitions = await db.rawQuery('''
      SELECT rowId, definition, pos FROM definition 
      WHERE wordId = ?
    ''', [
      word.id,
    ]);

    final definitions = <WordDefinition>[];

    for (final row in qDefinitions) {
      final definitionId = row['rowid'] as int;
      final definition = row['definition'] as String;
      final pos = row['pos'] as String;

      final qExamples = await db.rawQuery('''
        SELECT example FROM example WHERE definitionId = ?
      ''', [
        definitionId,
      ]);

      final examples = <String>[];

      for (final row in qExamples) {
        final example = row['example'] as String;

        examples.add(example);
      }

      definitions.add(WordDefinition(
        definition: definition,
        examples: UnmodifiableListView(examples),
        pos: posMap[pos]!,
      ));
    }

    final userData = await _fetchUserWordData(word.id);

    return WordCard(
      dictionaryEntry: DictionaryEntry(
        definitions: UnmodifiableListView(definitions),
        word: word,
      ),
      userData: userData,
    );
  }

  @override
  Future<void> setWordCardRepetitions(Word word, int repetitions) async {
    final db = await this.db;

    final count = await db.rawUpdate('''
      UPDATE up.userWords
      SET repetitions = ?
      WHERE wordId = ?
    ''', [
      repetitions,
      word.id,
    ]);

    if (count == 0) {
      _addWordToUserWords(word, repetitions);
    }

    assert(() {
      if (count > 1) {
        debugPrint('setWordCardRepetitions: count > 1');
      }

      return true;
    }());
  }

  @override
  Future<void> setWordCardStatus(
    Word word,
    WordCardStatus status,
  ) async {
    final db = await this.db;

    final count = await db.update(
      'up.userWords',
      {
        'status': _wordStatusToText[status],
        'lastRepetition': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'wordId = ?',
      whereArgs: [word.id],
    );

    if (count == 0) {
      await _addWordToUserWords(word);
    }

    assert(() {
      if (count > 1) {
        debugPrint('setWordCardStatus: count > 1');
      }

      return true;
    }());
  }

  Future<void> _addWordToUserWords(Word word, [int repetitions = 0]) async {
    final db = await this.db;

    assert(
      await () async {
        final qWords = await db.query(
          'word',
          columns: ['rowId, word'],
          where: 'rowId = ?',
          whereArgs: [word.id],
        );

        return qWords.isNotEmpty;
      }(),
      "insertNewWord: word doesn't exist in the dictionary",
    );

    final result = await db.rawInsert('''
        INSERT INTO up.userWords(wordId, word, repetitions, lastRepetition, status)
        VALUES (?, ?, ?, ?, ?)
      ''', [
      word.id,
      word.name,
      repetitions,
      DateTime.now().millisecondsSinceEpoch,
      _WordCardStatusText.learning,
    ]);

    assert(result != 0);
  }

  Future<WordCardUserData> _fetchUserWordData(int wordId) async {
    final db = await this.db;

    final qUserWords = await db.query(
      'up.userWords',
      columns: ['wordId', 'repetitions', 'status'],
      where: 'wordId = ?',
      whereArgs: [wordId],
    );

    if (qUserWords.isNotEmpty) {
      final row = qUserWords.first;

      return WordCardUserData(
        repetitionCount: row['repetitions'] as int,
        status: _textToWordStatus[row['status'] as String]!,
      );
    } else {
      return const WordCardUserData(
        repetitionCount: 0,
        status: WordCardStatus.unknown,
      );
    }
  }

  /// For hot reload - sqflite connection persists even after hotreload, so I
  /// get an error when attaching another database
  Future<void> _detachAllDb(Database mainConnection) async {
    final dbs = await mainConnection.rawQuery('''
      SELECT name FROM pragma_database_list
      WHERE name <> 'main'
    ''');

    for (final row in dbs) {
      final name = row['name'];
      mainConnection.execute('DETACH ?', [name]);
    }
  }

  Future<void> _attachUserProgressDb(Database mainConnection) async {
    debugPrint('attachUserProgressDb');

    final upPath = join(
      await getDatabasesPath(),
      'en_user_progress.db',
    );

    // wordId - references words in the dictionary db; **not a primary key**.
    final updb = await openDatabase(
      upPath,
      version: 4,
      onUpgrade: (db, _, __) {
        debugPrint('WordsRepository database onUpgrade()');

        db.execute('''DROP TABLE learning''');
        db.execute('''DROP TABLE known''');

        // status - see [_WordCardStatusText]
        db.execute('''
          CREATE TABLE userWords (
            wordId INTEGER UNIQUE NOT NULL,
            word TEXT, 
            repetitions INTEGER DEFAULT 0,
            lastRepetition INTEGER,
            status TEXT
          )
        ''');
      },
    );
    await updb.close();

    await mainConnection.execute('ATTACH ? AS up', [upPath]);
  }
}
