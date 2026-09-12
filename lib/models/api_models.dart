String _s(dynamic v) => v?.toString() ?? '';
double _n(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '0') ?? 0;
DateTime _date(dynamic v) =>
    DateTime.tryParse(v?.toString() ?? '') ??
    DateTime.fromMillisecondsSinceEpoch(0);
dynamic _j(Map<String, dynamic> j, String key) =>
    j[key] ??
    j[key.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '_${m[0]!.toLowerCase()}')];

class FieldInspection {
  final String id, plotId, overallStatus;
  final String? cycleId;
  final DateTime inspectionDate;
  final Map<String, bool> checklist;
  final String? notes, recommendation;
  final bool followUpRequired;
  final DateTime? followUpDate;
  final String? followUpTaskId, followUpStatus;

  const FieldInspection({
    required this.id,
    required this.plotId,
    required this.cycleId,
    required this.inspectionDate,
    required this.overallStatus,
    required this.checklist,
    this.notes,
    this.recommendation,
    required this.followUpRequired,
    this.followUpDate,
    this.followUpTaskId,
    this.followUpStatus,
  });

  factory FieldInspection.fromJson(Map<String, dynamic> j) {
    final rawChecklist = _j(j, 'checklist');
    final checklist = rawChecklist is Map
        ? rawChecklist.map(
            (key, value) => MapEntry(key.toString(), value == true),
          )
        : <String, bool>{};
    return FieldInspection(
      id: _s(_j(j, 'id')),
      plotId: _s(_j(j, 'plotId')),
      cycleId: _s(_j(j, 'cycleId')),
      inspectionDate: _date(_j(j, 'inspectionDate')),
      overallStatus: _s(_j(j, 'overallStatus')),
      checklist: checklist,
      notes: _j(j, 'notes')?.toString(),
      recommendation: _j(j, 'recommendation')?.toString(),
      followUpRequired: _j(j, 'followUpRequired') == true,
      followUpDate: _j(j, 'followUpDate') == null
          ? null
          : _date(_j(j, 'followUpDate')),
      followUpTaskId: _j(j, 'followUpTaskId')?.toString(),
      followUpStatus: _j(j, 'followUpStatus')?.toString(),
    );
  }
}

class ApiUser {
  final String id, email, role;
  final String? status;
  final String? firstName,
      lastName,
      birthDate,
      houseNumber,
      subdistrict,
      district,
      province,
      phone;
  const ApiUser({
    required this.id,
    required this.email,
    required this.role,
    this.status,
    this.firstName,
    this.lastName,
    this.birthDate,
    this.houseNumber,
    this.subdistrict,
    this.district,
    this.province,
    this.phone,
  });
  factory ApiUser.fromJson(Map<String, dynamic> j) => ApiUser(
    id: _s(j['id']),
    email: _s(j['email']),
    role: _s(j['role'] ?? 'farmer'),
    status: _j(j, 'status')?.toString(),
    firstName: _j(j, 'firstName')?.toString(),
    lastName: _j(j, 'lastName')?.toString(),
    birthDate: _j(j, 'birthDate')?.toString(),
    houseNumber: _j(j, 'houseNumber')?.toString(),
    subdistrict: _j(j, 'subdistrict')?.toString(),
    district: _j(j, 'district')?.toString(),
    province: _j(j, 'province')?.toString(),
    phone: _j(j, 'phone')?.toString(),
  );
}

class Plot {
  final String id, name, soil;
  final double area;
  final String? imageUrl;
  const Plot({
    required this.id,
    required this.name,
    required this.area,
    required this.soil,
    this.imageUrl,
  });
  factory Plot.fromJson(Map<String, dynamic> j) => Plot(
    id: _s(_j(j, 'id')),
    name: _s(_j(j, 'name')),
    area: _n(_j(j, 'area')),
    soil: _s(_j(j, 'soil')),
    imageUrl: _j(j, 'imageUrl')?.toString(),
  );
}

class Attachment {
  final String id, parentType, parentId, contentType, contentUrl;
  final int sizeBytes;
  final DateTime createdAt;
  const Attachment({
    required this.id,
    required this.parentType,
    required this.parentId,
    required this.contentType,
    required this.sizeBytes,
    required this.createdAt,
    required this.contentUrl,
  });
  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
    id: _s(_j(j, 'id')),
    parentType: _s(_j(j, 'parentType')),
    parentId: _s(_j(j, 'parentId')),
    contentType: _s(_j(j, 'contentType')),
    sizeBytes: (_j(j, 'sizeBytes') as num?)?.toInt() ?? 0,
    createdAt: _date(_j(j, 'createdAt')),
    contentUrl: _s(_j(j, 'contentUrl')),
  );
}

class ProductionCycle {
  final String id,
      name,
      plotId,
      plotName,
      cropType,
      variety,
      plantingMethod,
      status;
  final DateTime startDate;
  const ProductionCycle({
    required this.id,
    required this.name,
    required this.plotId,
    required this.plotName,
    required this.cropType,
    required this.variety,
    required this.plantingMethod,
    required this.startDate,
    required this.status,
  });
  factory ProductionCycle.fromJson(Map<String, dynamic> j) => ProductionCycle(
    id: _s(_j(j, 'id')),
    name: _s(_j(j, 'name')),
    plotId: _s(_j(j, 'plotId')),
    plotName: _s(_j(j, 'plotName')),
    cropType: _s(_j(j, 'cropType')),
    variety: _s(_j(j, 'variety')),
    plantingMethod: _s(_j(j, 'plantingMethod')),
    startDate: _date(_j(j, 'startDate')),
    status: _s(_j(j, 'status')),
  );
}

class Activity {
  final String id, cycleId, type;
  final String? description, imageUrl;
  final DateTime date, createdAt;
  const Activity({
    required this.id,
    required this.cycleId,
    required this.type,
    this.description,
    required this.date,
    required this.createdAt,
    this.imageUrl,
  });
  factory Activity.fromJson(Map<String, dynamic> j) => Activity(
    id: _s(_j(j, 'id')),
    cycleId: _s(_j(j, 'cycleId')),
    type: _s(_j(j, 'type')),
    description: _j(j, 'description')?.toString(),
    date: _date(_j(j, 'date')),
    createdAt: _date(_j(j, 'createdAt')),
    imageUrl: _j(j, 'imageUrl')?.toString(),
  );
}

class FarmerTransaction {
  final String id, type, category, item;
  final double amount;
  final DateTime date;
  final String? cycleId, fuelRecordId;
  const FarmerTransaction({
    required this.id,
    required this.type,
    required this.category,
    required this.item,
    required this.amount,
    required this.date,
    this.cycleId,
    this.fuelRecordId,
  });
  factory FarmerTransaction.fromJson(Map<String, dynamic> j) =>
      FarmerTransaction(
        id: _s(_j(j, 'id')),
        type: _s(_j(j, 'type')),
        category: _s(_j(j, 'category')),
        item: _s(_j(j, 'item')),
        amount: _n(_j(j, 'amount')),
        date: _date(_j(j, 'date')),
        cycleId: _j(j, 'cycleId')?.toString(),
        fuelRecordId: _j(j, 'fuelRecordId')?.toString(),
      );
}

class Vehicle {
  final String id, name, category;
  final String? licensePlate, color, details;
  const Vehicle({
    required this.id,
    required this.name,
    required this.category,
    this.licensePlate,
    this.color,
    this.details,
  });
  factory Vehicle.fromJson(Map<String, dynamic> j) => Vehicle(
    id: _s(_j(j, 'id')),
    name: _s(_j(j, 'name')),
    category: _s(_j(j, 'category')),
    licensePlate: _j(j, 'licensePlate')?.toString(),
    color: _j(j, 'color')?.toString(),
    details: _j(j, 'details')?.toString(),
  );
}

class FuelRecord {
  final String id, vehicleId, fuelType;
  final double amount;
  final DateTime date;
  final String? details;
  final double? odometer;
  const FuelRecord({
    required this.id,
    required this.vehicleId,
    required this.date,
    required this.fuelType,
    required this.amount,
    this.details,
    this.odometer,
  });
  factory FuelRecord.fromJson(Map<String, dynamic> j) => FuelRecord(
    id: _s(_j(j, 'id')),
    vehicleId: _s(_j(j, 'vehicleId')),
    date: _date(_j(j, 'date')),
    fuelType: _s(_j(j, 'fuelType')),
    amount: _n(_j(j, 'amount')),
    details: _j(j, 'details')?.toString(),
    odometer: _j(j, 'odometer') == null ? null : _n(_j(j, 'odometer')),
  );
}

class FarmerTask {
  final String id, name, cycleId, status;
  final DateTime dueDate;
  final String? description, fieldInspectionId;
  final bool isAutomaticFollowUp;
  const FarmerTask({
    required this.id,
    required this.name,
    required this.cycleId,
    required this.dueDate,
    required this.status,
    this.description,
    this.fieldInspectionId,
    this.isAutomaticFollowUp = false,
  });
  factory FarmerTask.fromJson(Map<String, dynamic> j) => FarmerTask(
    id: _s(_j(j, 'id')),
    name: _s(_j(j, 'name')),
    cycleId: _s(_j(j, 'cycleId')),
    dueDate: _date(_j(j, 'dueDate')),
    status: _s(_j(j, 'status')),
    description: _j(j, 'description')?.toString(),
    fieldInspectionId: _j(j, 'fieldInspectionId')?.toString(),
    isAutomaticFollowUp: _j(j, 'isAutomaticFollowUp') == true,
  );
}

class CycleSummaryActivity {
  final String id, type;
  final String? description;
  final DateTime date;
  const CycleSummaryActivity({
    required this.id,
    required this.type,
    required this.description,
    required this.date,
  });
  factory CycleSummaryActivity.fromJson(Map<String, dynamic> j) =>
      CycleSummaryActivity(
        id: _s(_j(j, 'id')),
        type: _s(_j(j, 'type')),
        description: _j(j, 'description')?.toString(),
        date: _date(_j(j, 'date')),
      );
}

class CycleSummaryTask {
  final String id, name, status;
  final String? description;
  final DateTime dueDate;
  const CycleSummaryTask({
    required this.id,
    required this.name,
    required this.status,
    required this.description,
    required this.dueDate,
  });
  factory CycleSummaryTask.fromJson(Map<String, dynamic> j) => CycleSummaryTask(
    id: _s(_j(j, 'id')),
    name: _s(_j(j, 'name')),
    status: _s(_j(j, 'status')),
    description: _j(j, 'description')?.toString(),
    dueDate: _date(_j(j, 'dueDate')),
  );
}

class CycleSummaryTransaction {
  final String id, type, category, item;
  final double amount;
  final DateTime date;
  final String? fuelRecordId;
  const CycleSummaryTransaction({
    required this.id,
    required this.type,
    required this.category,
    required this.item,
    required this.amount,
    required this.date,
    this.fuelRecordId,
  });
  factory CycleSummaryTransaction.fromJson(Map<String, dynamic> j) =>
      CycleSummaryTransaction(
        id: _s(_j(j, 'id')),
        type: _s(_j(j, 'type')),
        category: _s(_j(j, 'category')),
        item: _s(_j(j, 'item')),
        amount: _n(_j(j, 'amount')),
        date: _date(_j(j, 'date')),
        fuelRecordId: _j(j, 'fuelRecordId')?.toString(),
      );
}

class ProductionCycleSummary {
  final String cycleId, cycleName, plotName, status;
  final DateTime startDate;
  final DateTime? endDate;
  final int activityCount, taskCount, completedTaskCount;
  final double income, expense, profit;
  final List<CycleSummaryActivity> activities;
  final List<CycleSummaryTask> tasks;
  final List<CycleSummaryTransaction> transactions;
  const ProductionCycleSummary({
    required this.cycleId,
    required this.cycleName,
    required this.plotName,
    required this.status,
    required this.startDate,
    required this.endDate,
    required this.activityCount,
    required this.taskCount,
    required this.completedTaskCount,
    required this.income,
    required this.expense,
    required this.profit,
    required this.activities,
    required this.tasks,
    required this.transactions,
  });
  factory ProductionCycleSummary.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> rows(String key) {
      final raw = _j(j, key);
      return raw is List
          ? raw
                .whereType<Map>()
                .map((x) => Map<String, dynamic>.from(x))
                .toList()
          : const [];
    }

    return ProductionCycleSummary(
      cycleId: _s(_j(j, 'cycleId')),
      cycleName: _s(_j(j, 'cycleName')),
      plotName: _s(_j(j, 'plotName')),
      status: _s(_j(j, 'status')),
      startDate: _date(_j(j, 'startDate')),
      endDate: _j(j, 'endDate') == null ? null : _date(_j(j, 'endDate')),
      activityCount: (_j(j, 'activityCount') as num?)?.toInt() ?? 0,
      taskCount: (_j(j, 'taskCount') as num?)?.toInt() ?? 0,
      completedTaskCount: (_j(j, 'completedTaskCount') as num?)?.toInt() ?? 0,
      income: _n(_j(j, 'income')),
      expense: _n(_j(j, 'expense')),
      profit: _n(_j(j, 'profit')),
      activities: rows(
        'activities',
      ).map(CycleSummaryActivity.fromJson).toList(),
      tasks: rows('tasks').map(CycleSummaryTask.fromJson).toList(),
      transactions: rows('transactions')
          .map(CycleSummaryTransaction.fromJson)
          .where((x) => x.fuelRecordId == null)
          .toList(),
    );
  }
  int get pendingTaskCount => taskCount - completedTaskCount;
}

class FarmerNotification {
  final String id, kind, title, body;
  final String? taskId, taskName, cycleName, plotName;
  final String? announcementImageId, announcementType;
  final DateTime? dueDate;
  final DateTime createdAt;
  final DateTime? readAt;
  const FarmerNotification({
    required this.id,
    required this.taskId,
    required this.taskName,
    required this.cycleName,
    required this.plotName,
    required this.kind,
    required this.title,
    required this.body,
    this.announcementImageId,
    this.announcementType,
    required this.dueDate,
    required this.createdAt,
    this.readAt,
  });
  factory FarmerNotification.fromJson(Map<String, dynamic> j) =>
      FarmerNotification(
        id: _s(_j(j, 'id')),
        taskId: _j(j, 'taskId') == null ? null : _s(_j(j, 'taskId')),
        taskName: _j(j, 'taskName') == null ? null : _s(_j(j, 'taskName')),
        cycleName: _j(j, 'cycleName') == null ? null : _s(_j(j, 'cycleName')),
        plotName: _j(j, 'plotName') == null ? null : _s(_j(j, 'plotName')),
        kind: _s(_j(j, 'kind')),
        title: _s(_j(j, 'title')),
        body: _s(_j(j, 'body')),
        announcementImageId: _j(j, 'announcementImageId')?.toString(),
        announcementType: _j(j, 'announcementType')?.toString(),
        dueDate: _j(j, 'dueDate') == null ? null : _date(_j(j, 'dueDate')),
        createdAt: _date(_j(j, 'createdAt')),
        readAt: _j(j, 'readAt') == null ? null : _date(_j(j, 'readAt')),
      );
  bool get isRead => readAt != null;
}

class Categories {
  final List<String> activityCategories,
      expenseCategories,
      incomeCategories,
      soilTypes,
      plantingTypes,
      cropTypes,
      vehicleCategories;
  const Categories({
    this.activityCategories = const [],
    this.expenseCategories = const [],
    this.incomeCategories = const [],
    this.soilTypes = const [],
    this.plantingTypes = const [],
    this.cropTypes = const [],
    this.vehicleCategories = const [],
  });
  factory Categories.fromJson(Map<String, dynamic> j) => Categories(
    activityCategories: List<String>.from(_j(j, 'activityCategories') ?? []),
    expenseCategories: List<String>.from(_j(j, 'expenseCategories') ?? []),
    incomeCategories: List<String>.from(_j(j, 'incomeCategories') ?? []),
    soilTypes: List<String>.from(_j(j, 'soilTypes') ?? []),
    plantingTypes: List<String>.from(_j(j, 'plantingTypes') ?? []),
    cropTypes: List<String>.from(_j(j, 'cropTypes') ?? []),
    vehicleCategories: List<String>.from(_j(j, 'vehicleCategories') ?? []),
  );
}
