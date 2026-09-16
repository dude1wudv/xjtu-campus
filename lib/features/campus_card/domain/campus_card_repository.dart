import 'campus_card.dart';

abstract class CampusCardRepository {
  Future<CampusCardSnapshot> load();
}
