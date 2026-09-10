import 'package:flutter/foundation.dart';
import '../services/api_session.dart';

class CategoryProvider extends ChangeNotifier {
  final ApiSession session;
  CategoryProvider(this.session);
  List<String> activityCategories = [],
      expenseCategories = [],
      incomeCategories = [],
      soilTypes = [],
      plantingTypes = [],
      cropTypes = [],
      vehicleCategories = [];
  Future<void> load() async {
    final c = await session.api.categories();
    activityCategories = c.activityCategories;
    expenseCategories = c.expenseCategories;
    incomeCategories = c.incomeCategories;
    soilTypes = c.soilTypes;
    plantingTypes = c.plantingTypes;
    cropTypes = c.cropTypes;
    vehicleCategories = c.vehicleCategories;
    notifyListeners();
  }
}
