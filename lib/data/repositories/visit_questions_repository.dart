import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// أسئلة العيلة للدكتور (D3.8) — محلي.
class VisitQuestionsRepository {
  VisitQuestionsRepository(this._db);

  final AppDatabase _db;

  /// اللي لسه ما اتسألش الأول، وبعدين الأحدث.
  Stream<List<VisitQuestionRow>> watch(int patientId) => (_db.select(_db.visitQuestions)
        ..where((t) => t.patientId.equals(patientId))
        ..orderBy([(t) => OrderingTerm.asc(t.asked), (t) => OrderingTerm.desc(t.createdAt)]))
      .watch();

  Future<void> add(int patientId, String body, {required DateTime now}) {
    final text = body.trim();
    if (text.isEmpty) throw ArgumentError.value(body, 'body', 'السؤال فاضي');
    return _db.into(_db.visitQuestions).insert(
          VisitQuestionsCompanion.insert(patientId: patientId, body: text, createdAt: now),
        );
  }

  Future<void> setAsked(int id, bool asked) =>
      (_db.update(_db.visitQuestions)..where((t) => t.id.equals(id))).write(VisitQuestionsCompanion(asked: Value(asked)));

  Future<void> remove(int id) => (_db.delete(_db.visitQuestions)..where((t) => t.id.equals(id))).go();
}
