import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'food_item.dart';
import 'models.dart';
import 'onboarding_screen.dart';

/// 이미 다른 사용자가 쓰고 있는 닉네임으로 [FirestoreService.updateNickname]을
/// 호출했을 때 던져진다.
class NicknameTakenException implements Exception {
  const NicknameTakenException();
}

/// 매크로 목표의 출처. 수동 편집 후에는 자동 재계산이 값을 덮지 않는다.
enum GoalsSource { auto, manual }

/// 월별 캘린더에 표시할 하루 목표 달성 정도.
/// [none]은 그날 기록이 없거나(끼니에 음식 없음), 저장 당시 목표 스냅샷이
/// 없는(이 기능 출시 이전 기록) 경우로, 점을 표시하지 않는다.
enum GoalAchievement { none, good, warn, bad }

/// Firestore 기반 데이터 레이어. [StorageService](구 Hive 버전)대체
///
/// 화면 코드는 대부분 동기 함수(`loadXxx`/`saveXxx`)를 그대로 호출할 수 있도록,
/// 로그인 직후 [init]에서 사용자 문서 + 식사 기록을 인메모리 캐시로 미리 읽어온 뒤
/// 그 캐시를 기준으로 값을 읽고, 쓰기는 캐시 갱신과 동시에 Firestore로 write-through한다.
/// 또한 사용자 문서/식사 컬렉션에 실시간 리스너를 걸어 다른 기기에서 생긴 변경을
/// [changes] 스트림으로 알려준다.
class FirestoreService {
  FirestoreService._();

  static const _defaultMealNames = ['아침', '점심', '저녁'];

  static String? _uid;
  static Map<String, dynamic> _userDoc = {};
  static Map<String, dynamic> _subscriptionDoc = {};
  static final Map<String, List<MealEntry>> _mealsCache = {};
  /// 날짜별 끼니 저장 시점의 목표 kcal 스냅샷. 월별 캘린더의 달성 여부 표시에 쓰인다.
  static final Map<String, double> _goalKcalCache = {};

  static StreamSubscription? _userSub;
  static StreamSubscription? _mealsSub;
  static StreamSubscription? _subscriptionSub;

  static final StreamController<void> _changesController =
      StreamController<void>.broadcast();

  /// 다른 기기에서(또는 실시간 리스너를 통해) 데이터가 바뀌었을 때 발생하는 스트림.
  /// 화면에서 구독해 다시 그리면 다중 기기 동기화가 반영된다.
  static Stream<void> get changes => _changesController.stream;

  static bool get isReady => _uid != null;

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _userRef(String uid) =>
      _db.collection('users').doc(uid);

  /// 구독(Pro) 상태 문서. App Store Server API/Notifications를 처리하는
  /// Cloud Functions(Admin SDK)만 쓸 수 있다 — 클라이언트는 읽기 전용.
  static DocumentReference<Map<String, dynamic>> _subscriptionRef(
    String uid,
  ) => _db.collection('subscriptions').doc(uid);

  /// Firebase Auth 세션에서 소셜 로그인 제공자 저장
  /// 반환값: `google` / `apple` / `kakao` / null
  static String? resolveAuthProvider() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    if (user.uid.startsWith('kakao:')) return 'kakao';
    for (final p in user.providerData) {
      switch (p.providerId) {
        case 'google.com':
          return 'google';
        case 'apple.com':
          return 'apple';
      }
    }
    return null;
  }

  // --- 초기화 / 해제 ---

  /// 콜드 스타트 직후엔 App Check 토큰이 준비되기 전이라 첫 get()이
  /// permission-denied / unavailable 로 실패할 수 있다. 여기서 사용자 문서를
  /// 못 읽으면 온보딩 완료 여부를 알 수 없어 사용자가 온보딩 화면으로
  /// 되돌아가므로, 짧게 재시도하고 그래도 안 되면 로컬 캐시라도 읽는다.
  static Future<DocumentSnapshot<Map<String, dynamic>>> _getUserDocResilient(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    Object? lastErr;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        return await ref.get();
      } catch (e) {
        lastErr = e;
        debugPrint('FirestoreService: 사용자 문서 get 실패 ($attempt/3): $e');
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
    }
    try {
      final cached = await ref.get(const GetOptions(source: Source.cache));
      debugPrint('FirestoreService: 서버 실패 → 로컬 캐시에서 사용자 문서 로드');
      return cached;
    } catch (_) {
      throw lastErr ?? StateError('사용자 문서를 불러오지 못했습니다.');
    }
  }

  /// 로그인 직후 호출. 사용자 문서와 식사 기록을 모두 읽어와 캐시를 채우고,
  /// 이후 변경 사항을 실시간으로 반영하는 리스너를 등록한다.
  static Future<void> init(String uid) async {
    await dispose();
    _uid = uid;
    final ref = _userRef(uid);
    final authProvider = resolveAuthProvider();

    final authNickname =
        FirebaseAuth.instance.currentUser?.displayName?.trim();
    final hasAuthNickname =
        authNickname != null && authNickname.isNotEmpty;

    final snap = await _getUserDocResilient(ref);
    if (!snap.exists) {
      final created = <String, dynamic>{
        'onboardingCompleted': false,
        'createdAt': FieldValue.serverTimestamp(),
        'authProvider': ?authProvider,
        if (hasAuthNickname) 'nickname': authNickname,
      };
      await ref.set(created);
      _userDoc = {
        'onboardingCompleted': false,
        'authProvider': ?authProvider,
        if (hasAuthNickname) 'nickname': authNickname,
      };
    } else {
      _userDoc = snap.data() ?? {};
      final patch = <String, dynamic>{};
      if (authProvider != null && _userDoc['authProvider'] != authProvider) {
        patch['authProvider'] = authProvider;
      }
      final storedNickname = (_userDoc['nickname'] as String?)?.trim();
      if ((storedNickname == null || storedNickname.isEmpty) &&
          hasAuthNickname) {
        patch['nickname'] = authNickname;
      }
      if (patch.isNotEmpty) {
        _userDoc = {..._userDoc, ...patch};
        await ref.set(patch, SetOptions(merge: true));
      }
    }

    final mealsSnap = await ref.collection('meals').get();
    for (final doc in mealsSnap.docs) {
      _mealsCache[doc.id] = _decodeMeals(doc.data());
      final goalKcal = _decodeGoalKcal(doc.data());
      if (goalKcal != null) _goalKcalCache[doc.id] = goalKcal;
    }

    final subSnap = await _subscriptionRef(uid).get();
    _subscriptionDoc = subSnap.data() ?? {};

    _userSub = ref.snapshots().listen(
      (doc) {
        _userDoc = doc.data() ?? {};
        _changesController.add(null);
      },
      onError: (Object e) {
        debugPrint('FirestoreService: 사용자 문서 listen 오류: $e');
      },
    );
    _mealsSub = ref.collection('meals').snapshots().listen(
      (qs) {
        for (final change in qs.docChanges) {
          final data = change.doc.data() ?? {};
          _mealsCache[change.doc.id] = _decodeMeals(data);
          final goalKcal = _decodeGoalKcal(data);
          if (goalKcal != null) {
            _goalKcalCache[change.doc.id] = goalKcal;
          } else {
            _goalKcalCache.remove(change.doc.id);
          }
        }
        _changesController.add(null);
      },
      onError: (Object e) {
        debugPrint('FirestoreService: 식사 기록 listen 오류: $e');
      },
    );

    _subscriptionSub = _subscriptionRef(uid).snapshots().listen(
      (doc) {
        _subscriptionDoc = doc.data() ?? {};
        _changesController.add(null);
      },
      onError: (Object e) {
        debugPrint('FirestoreService: 구독 상태 listen 오류: $e');
      },
    );
  }

  /// 로그아웃 시 캐시와 리스너를 모두 정리한다.
  static Future<void> dispose() async {
    await _userSub?.cancel();
    await _mealsSub?.cancel();
    await _subscriptionSub?.cancel();
    _userSub = null;
    _mealsSub = null;
    _subscriptionSub = null;
    _uid = null;
    _userDoc = {};
    _subscriptionDoc = {};
    _mealsCache.clear();
    _goalKcalCache.clear();
  }

  static void _writeUser(Map<String, dynamic> patch) {
    final uid = _uid;
    if (uid == null) return;
    _userRef(
      uid,
    ).set(patch, SetOptions(merge: true)).catchError((Object e) {
      debugPrint('FirestoreService: 사용자 문서 저장 실패: $e');
    });
  }

  static List<MealEntry> _decodeMeals(Map<String, dynamic> data) {
    final raw = data['entries'] as List? ?? const [];
    return raw.map((e) => MealEntry.fromMap(e as Map)).toList();
  }

  static double? _decodeGoalKcal(Map<String, dynamic> data) =>
      (data['goalKcal'] as num?)?.toDouble();

  static List<MealEntry> _defaultMealsForDay() => _defaultMealNames
      .map((n) => MealEntry(name: n, isFixed: true))
      .toList();

  // --- 식사 목록 (날짜별) ---

  static String dateStorageKey(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static List<MealEntry> loadMealsForDate(DateTime date) {
    final key = dateStorageKey(date);
    final cached = _mealsCache[key];
    if (cached == null || cached.isEmpty) return _defaultMealsForDay();
    return cached;
  }

  /// [goalKcal]은 저장 시점에 적용 중이던 목표 총 kcal 스냅샷.
  /// 월별 캘린더에서 그날의 달성 여부를 판단할 때, "지금" 목표가 아니라
  /// 기록 당시 목표와 비교하기 위해 함께 저장한다.
  static void saveMealsForDate(
    DateTime date,
    List<MealEntry> meals, {
    required double goalKcal,
  }) {
    final key = dateStorageKey(date);
    _mealsCache[key] = meals;
    _goalKcalCache[key] = goalKcal;
    final uid = _uid;
    if (uid == null) return;
    _userRef(uid)
        .collection('meals')
        .doc(key)
        .set({
          'entries': meals.map((m) => m.toMap()).toList(),
          'goalKcal': goalKcal,
        })
        .catchError((Object e) {
          debugPrint('FirestoreService: 식사 기록 저장 실패: $e');
        });
  }

  // --- 월별 캘린더 달성 여부 ---

  static double _intakeKcalForKey(String key) {
    final meals = _mealsCache[key];
    if (meals == null) return 0;
    return meals.fold<double>(
      0,
      (total, m) => total + m.foods.fold(0.0, (s, f) => s + f.kcal),
    );
  }

  static bool hasRecordForDate(DateTime date) {
    final meals = _mealsCache[dateStorageKey(date)];
    if (meals == null) return false;
    return meals.any((m) => m.foods.isNotEmpty);
  }

  /// 그날 기록이 없거나 목표 스냅샷이 없으면 [GoalAchievement.none].
  /// 실제 섭취 kcal과 저장 당시 목표 kcal의 차이가 ±100 이내면 [good],
  /// ±300 이내면 [warn], 그 밖이면 [bad].
  static GoalAchievement achievementForDate(DateTime date) {
    if (!hasRecordForDate(date)) return GoalAchievement.none;
    final key = dateStorageKey(date);
    final goalKcal = _goalKcalCache[key];
    if (goalKcal == null) return GoalAchievement.none;
    final diff = (_intakeKcalForKey(key) - goalKcal).abs();
    if (diff <= 100) return GoalAchievement.good;
    if (diff <= 300) return GoalAchievement.warn;
    return GoalAchievement.bad;
  }

  // --- 마이 식단 (자주 먹는 음식 즐겨찾기) ---

  static List<MyDietItem> loadMyDiet() {
    final raw = _userDoc['myDiet'] as List?;
    if (raw == null) return const [];
    return raw.whereType<Map>().map((e) => MyDietItem.fromMap(e)).toList();
  }

  static void _writeMyDiet(List<MyDietItem> items) {
    final list = items.map((e) => e.toMap()).toList();
    _userDoc = {..._userDoc, 'myDiet': list};
    _writeUser({'myDiet': list});
  }

  static bool isInMyDiet(FoodItem item) =>
      loadMyDiet().any((e) => MyDietItem.sameFood(e.food, item));

  /// 이미 저장된 음식이면 아무 것도 하지 않는다(중복 방지).
  static void addToMyDiet(FoodItem item) {
    final items = loadMyDiet();
    if (items.any((e) => MyDietItem.sameFood(e.food, item))) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    _writeMyDiet([...items, MyDietItem(id: id, food: item)]);
  }

  static void removeFromMyDietMatching(FoodItem item) {
    final items = loadMyDiet()
      ..removeWhere((e) => MyDietItem.sameFood(e.food, item));
    _writeMyDiet(items);
  }

  static void removeFromMyDietById(String id) {
    final items = loadMyDiet()..removeWhere((e) => e.id == id);
    _writeMyDiet(items);
  }

  // --- 목표 수치 ---

  /// 매크로 목표가 프로필 기반 자동 계산인지, 사용자가 직접 수정한 값인지.
  /// 수동(`manual`)이면 대시보드가 동기화 때 자동 재계산으로 덮어쓰지 않는다.
  static GoalsSource loadGoalsSource() {
    final raw = _goals?['source'] as String?;
    if (raw == GoalsSource.manual.name) return GoalsSource.manual;
    // 필드가 없거나 알 수 없으면 auto — 온보딩 직후·동적 목표 유지가 기본.
    return GoalsSource.auto;
  }

  static Map<String, dynamic>? get _goals =>
      _userDoc['goals'] as Map<String, dynamic>?;

  static double loadCarbGoal() =>
      (_goals?['carbGoal'] as num?)?.toDouble() ?? 410.0;

  static double loadProteinGoal() =>
      (_goals?['proteinGoal'] as num?)?.toDouble() ?? 140.0;

  static double loadFatGoal() =>
      (_goals?['fatGoal'] as num?)?.toDouble() ?? 70.0;

  static void saveGoals({
    required double carb,
    required double protein,
    required double fat,
    required GoalsSource source,
  }) {
    final goals = {
      'carbGoal': carb,
      'proteinGoal': protein,
      'fatGoal': fat,
      'source': source.name,
    };
    _userDoc = {..._userDoc, 'goals': goals};
    _writeUser({'goals': goals});
  }

  // --- 알림 설정 ---

  /// 설정 > 알림 설정의 "하루 기록 리마인더"(매일 저녁 8시 고정) on/off.
  /// 로컬이 아니라 서버(Cloud Functions 예약 함수)가 이 값을 보고 그날 기록
  /// 여부를 직접 확인한 뒤 FCM 푸시를 보낸다.
  static bool loadDailyReminderEnabled() =>
      _userDoc['dailyReminderEnabled'] as bool? ?? false;

  static void saveDailyReminderEnabled(bool enabled) {
    _userDoc = {..._userDoc, 'dailyReminderEnabled': enabled};
    _writeUser({'dailyReminderEnabled': enabled});
  }

  /// 하루 기록 리마인더 푸시를 받을 기기의 FCM 토큰 목록(멀티 기기 지원).
  /// 로컬 캐시([_userDoc])는 서버 전용 필드라 굳이 갱신하지 않는다.
  static void addFcmToken(String token) {
    final uid = _uid;
    if (uid == null) return;
    _userRef(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true)).catchError((Object e) {
      debugPrint('FirestoreService: FCM 토큰 저장 실패: $e');
    });
  }

  static void removeFcmToken(String token) {
    final uid = _uid;
    if (uid == null) return;
    _userRef(uid).set({
      'fcmTokens': FieldValue.arrayRemove([token]),
    }, SetOptions(merge: true)).catchError((Object e) {
      debugPrint('FirestoreService: FCM 토큰 삭제 실패: $e');
    });
  }

  /// 나만의 습관 알림 목록(이모지·이름·시간·요일을 직접 정하는 리마인더 여러 개).
  static List<HabitReminder> loadHabitReminders() {
    final raw = _userDoc['habitReminders'] as List?;
    if (raw == null) return const [];
    return raw.map((e) => HabitReminder.fromMap(e as Map)).toList();
  }

  static void saveHabitReminders(List<HabitReminder> reminders) {
    final list = reminders.map((r) => r.toMap()).toList();
    _userDoc = {..._userDoc, 'habitReminders': list};
    _writeUser({'habitReminders': list});
  }

  // --- 온보딩 ---

  static bool loadOnboardingCompleted() =>
      _userDoc['onboardingCompleted'] as bool? ?? false;

  // --- 도움말 튜토리얼 ---

  static bool loadHelpTutorialSeen() =>
      _userDoc['helpTutorialSeen'] as bool? ?? false;

  /// 도움말 튜토리얼을 봤다고 표시한다. 다시 안 뜨는 게 중요하므로
  /// (앱을 곧바로 종료해도) 서버 반영까지 기다린다.
  static Future<void> markHelpTutorialSeen() async {
    _userDoc = {..._userDoc, 'helpTutorialSeen': true};
    final uid = _uid;
    if (uid == null) return;
    await _userRef(uid).set(
      {'helpTutorialSeen': true},
      SetOptions(merge: true),
    );
  }

  // --- 하루 기록 리마인더 동의 화면 ---

  static bool loadReminderPromptSeen() =>
      _userDoc['reminderPromptSeen'] as bool? ?? false;

  /// 하루 기록 리마인더 알림 동의 화면을 봤다고 표시한다. 다시 안 뜨는 게
  /// 중요하므로(앱을 곧바로 종료해도) 서버 반영까지 기다린다.
  static Future<void> markReminderPromptSeen() async {
    _userDoc = {..._userDoc, 'reminderPromptSeen': true};
    final uid = _uid;
    if (uid == null) return;
    await _userRef(uid).set(
      {'reminderPromptSeen': true},
      SetOptions(merge: true),
    );
  }

  /// 온보딩 완료 시 프로필·목표·목표일·완료 플래그를 **한 번의 쓰기로** 저장하고
  /// 서버 반영까지 기다린다.
  ///
  /// 개별 fire-and-forget 저장으로 나누면 (1) 앱이 곧바로 종료될 때 일부만
  /// 반영돼 "온보딩은 끝났는데 프로필이 없는" 상태가 되거나 (2) 아예 아무것도
  /// 안 써진 채 다음 실행에서 온보딩이 다시 뜬다. 실패는 삼키지 않고 던져서
  /// 호출부가 재시도 UI를 띄우게 한다.
  static Future<void> completeOnboarding({
    required OnboardingResult profile,
    required double carbGoal,
    required double proteinGoal,
    required double fatGoal,
    required DateTime goalDate,
  }) async {
    final uid = _uid;
    if (uid == null) {
      throw StateError('로그인 상태가 아니라 온보딩을 저장할 수 없습니다.');
    }

    final profileMap = <String, dynamic>{
      'gender': profile.gender.name,
      'ageYears': profile.ageYears,
      'heightCm': profile.heightCm,
      'currentWeightKg': profile.startWeightKg,
      'goalWeightKg': profile.goalWeightKg,
      'activity': profile.activity.name,
      'purpose': profile.purpose.name,
    };
    final goalsMap = <String, dynamic>{
      'carbGoal': carbGoal,
      'proteinGoal': proteinGoal,
      'fatGoal': fatGoal,
      'source': GoalsSource.auto.name,
    };
    final goalDateIso = DateTime(
      goalDate.year,
      goalDate.month,
      goalDate.day,
    ).toIso8601String();

    final patch = <String, dynamic>{
      'profile': profileMap,
      'goals': goalsMap,
      'goalDateIso': goalDateIso,
      'onboardingCompleted': true,
    };

    await _userRef(uid).set(patch, SetOptions(merge: true));
    _userDoc = {..._userDoc, ...patch};
  }

  // --- 목표 날짜 ---

  static DateTime? loadGoalDate() {
    final iso = _userDoc['goalDateIso'] as String?;
    if (iso == null || iso.isEmpty) return null;
    return DateTime.tryParse(iso);
  }

  static void saveGoalDate(DateTime date) {
    final iso = DateTime(
      date.year,
      date.month,
      date.day,
    ).toIso8601String();
    _userDoc = {..._userDoc, 'goalDateIso': iso};
    _writeUser({'goalDateIso': iso});
  }

  // --- 닉네임 ---

  static String? loadNickname() {
    final stored = (_userDoc['nickname'] as String?)?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    final authName =
        FirebaseAuth.instance.currentUser?.displayName?.trim();
    if (authName != null && authName.isNotEmpty) return authName;
    return null;
  }

  static void saveNickname(String nickname) {
    final trimmed = nickname.trim();
    if (trimmed.isEmpty) return;
    _userDoc = {..._userDoc, 'nickname': trimmed};
    _writeUser({'nickname': trimmed});
  }

  /// Apple 로그인은 최초 인증 시에만 이름을 내려주므로, [AuthService]가 로그인
  /// 성공 직후 그 이름으로 이 함수를 호출해 닉네임을 미리 채워둔다.
  ///
  /// [init]이 로그인 상태 변화를 감지해 먼저 실행되는 타이밍(authStateChanges
  /// 리스너와의 경쟁 상태)에 영향받지 않도록, 캐시(`_userDoc`)가 아니라
  /// Firestore 문서를 직접 읽고 쓴다. 이미 닉네임이 있으면(사용자가 직접
  /// 정했거나 이미 채워진 경우) 덮어쓰지 않는다.
  static Future<void> seedNicknameIfMissing(
    String uid,
    String nickname,
  ) async {
    final trimmed = nickname.trim();
    if (trimmed.isEmpty) return;
    final ref = _userRef(uid);
    final snap = await ref.get();
    final existing = (snap.data()?['nickname'] as String?)?.trim();
    if (existing != null && existing.isNotEmpty) return;
    await ref.set({'nickname': trimmed}, SetOptions(merge: true));
  }

  /// 중복확인용 정규화: 트림 + 소문자 + 공백 제거.
  /// Cloud Function(`updateNickname`)의 정규화 로직과 반드시 동일하게 맞춘다.
  static String _normalizeNickname(String nickname) {
    return nickname.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }

  /// 타이핑 중 보여줄 가벼운 실시간 중복 힌트. `nicknames/{normalized}` 인덱스
  /// 문서를 직접 읽어 확인하며, 최종 저장 시의 원자적 중복확인을 대체하지 않는다.
  static Future<bool> isNicknameAvailable(String nickname) async {
    final normalized = _normalizeNickname(nickname);
    if (normalized.isEmpty) return false;
    final doc = await _db.collection('nicknames').doc(normalized).get();
    if (!doc.exists) return true;
    return doc.data()?['uid'] == _uid;
  }

  /// 닉네임을 서버(Cloud Function `updateNickname`)를 통해 원자적으로 갱신한다.
  /// 이미 다른 사용자가 쓰는 닉네임이면 [NicknameTakenException]을 던진다.
  static Future<void> updateNickname(String nickname) async {
    final trimmed = nickname.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('닉네임을 입력해 주세요.');
    }
    final callable = FirebaseFunctions.instanceFor(
      region: 'asia-northeast3',
    ).httpsCallable('updateNickname');
    try {
      await callable.call({'nickname': trimmed});
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'already-exists') {
        throw const NicknameTakenException();
      }
      rethrow;
    }
    _userDoc = {..._userDoc, 'nickname': trimmed};
    await FirebaseAuth.instance.currentUser?.reload();
  }

  // --- 사용자 프로필(온보딩 입력) ---
  // 프로필 저장은 completeOnboarding()에서 목표·완료 플래그와 함께 원자적으로 처리한다.

  static Map<String, dynamic>? get _profile =>
      _userDoc['profile'] as Map<String, dynamic>?;

  static OnboardingGender? loadGender() {
    final s = _profile?['gender'] as String?;
    if (s == null) return null;
    for (final v in OnboardingGender.values) {
      if (v.name == s) return v;
    }
    return null;
  }

  static int? loadAgeYears() => (_profile?['ageYears'] as num?)?.toInt();

  static double? loadHeightCm() =>
      (_profile?['heightCm'] as num?)?.toDouble();

  static double? loadCurrentWeightKg() =>
      (_profile?['currentWeightKg'] as num?)?.toDouble();

  static double? loadGoalWeightKg() =>
      (_profile?['goalWeightKg'] as num?)?.toDouble();

  static OnboardingActivity? loadActivity() {
    final s = _profile?['activity'] as String?;
    if (s == null) return null;
    for (final v in OnboardingActivity.values) {
      if (v.name == s) return v;
    }
    return null;
  }

  static OnboardingPurpose? loadPurpose() {
    final s = _profile?['purpose'] as String?;
    if (s == null) return null;
    for (final v in OnboardingPurpose.values) {
      if (v.name == s) return v;
    }
    return null;
  }

  // --- 구독(Pro) 상태 ---
  //
  // subscriptions/{uid} 문서는 App Store Server API/Notifications를 처리하는
  // Cloud Functions(Admin SDK)만 쓴다. 여기엔 일부러 saveXxx를 두지 않는다 —
  // 클라이언트가 자신의 구독 상태를 직접 켤 수 있는 경로를 만들지 않기 위함.

  static String? loadAppAccountToken() =>
      _userDoc['appAccountToken'] as String?;

  /// StoreKit2 구매 요청에 실어 보낼 appAccountToken을 준비한다. 이미
  /// 발급되어 있으면 그대로 반환하고(멱등), 없으면 Cloud Function
  /// (`getOrCreateAppAccountToken`, Admin SDK)을 통해 새로 발급받는다.
  /// 클라이언트가 이 값을 직접 만들어 쓰지 않는 이유는 users/{uid}의
  /// appAccountToken 필드가 rules에서 클라이언트 쓰기를 막아뒀기 때문이다.
  static Future<String> ensureAppAccountToken() async {
    final cached = loadAppAccountToken();
    if (cached != null && cached.isNotEmpty) return cached;

    final callable = FirebaseFunctions.instanceFor(
      region: 'asia-northeast3',
    ).httpsCallable('getOrCreateAppAccountToken');
    final result = await callable.call<Map<String, dynamic>>();
    final token = result.data['appAccountToken'] as String;
    _userDoc = {..._userDoc, 'appAccountToken': token};
    return token;
  }

  static bool loadIsPro() => _subscriptionDoc['isPro'] as bool? ?? false;

  static DateTime? loadProExpiresAt() {
    final ts = _subscriptionDoc['expiresAt'];
    if (ts is Timestamp) return ts.toDate();
    return null;
  }
}
