import 'dart:async';
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers:[ChangeNotifierProvider(create: (_) => AppState()..loadData())],
      child: const ProTestApp(),
    ),
  );
}

// ==========================================
// THEME: BRUTALIST PAPER AESTHETIC
// ==========================================
final Color paperBg = const Color(0xFFEBE3D5);
final Color inkBlack = const Color(0xFF1E1E1E);
final Color brassAccent = const Color(0xFFB58840);
final Color rustRed = const Color(0xFF9E3C27);
final Color steamGreen = const Color(0xFF385E38);

final ThemeData brutalistTheme = ThemeData(
  fontFamily: 'Courier',
  scaffoldBackgroundColor: paperBg,
  colorScheme: ColorScheme.light(
    primary: inkBlack,
    secondary: brassAccent,
    surface: paperBg,
    error: rustRed,
    onPrimary: paperBg,
    onSecondary: inkBlack,
    onSurface: inkBlack,
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: paperBg,
    foregroundColor: inkBlack,
    elevation: 0,
    centerTitle: true,
    shape: Border(bottom: BorderSide(color: inkBlack, width: 3)),
  ),
  cardTheme: CardTheme(
    color: paperBg,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.zero,
      side: BorderSide(color: inkBlack, width: 2),
    ),
    margin: const EdgeInsets.only(bottom: 16),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: inkBlack,
      foregroundColor: paperBg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      side: BorderSide(color: inkBlack, width: 2),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: inkBlack,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      side: BorderSide(color: inkBlack, width: 2),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: paperBg,
    border: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Colors.black, width: 2)),
    enabledBorder: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Colors.black, width: 2)),
    focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Colors.black, width: 3)),
  ),
  dialogTheme: DialogTheme(
    backgroundColor: paperBg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: Colors.black, width: 3)),
  ),
  drawerTheme: DrawerThemeData(
    backgroundColor: paperBg,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: Colors.black, width: 2)),
  ),
  dividerTheme: DividerThemeData(color: inkBlack, thickness: 2),
);

class ProTestApp extends StatelessWidget {
  const ProTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ProTest',
      debugShowCheckedModeBanner: false,
      theme: brutalistTheme,
      home: const MainNavigationScreen(),
    );
  }
}

// ==========================================
// MODELS
// ==========================================
class Question {
  final String id;
  String category;
  String subCategory;
  String text;
  List<String> options;
  int correctAnswerIndex;

  Question({required this.id, required this.category, required this.subCategory, required this.text, required this.options, required this.correctAnswerIndex});

  factory Question.fromJson(Map<String, dynamic> json) => Question(
        id: json['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
        category: json['category'] ?? 'Uncategorized',
        subCategory: json['subCategory'] ?? 'General',
        text: json['text'] ?? '',
        options: List<String>.from(json['options'] ?? []),
        correctAnswerIndex: json['correctAnswerIndex'] ?? 0,
      );

  Map<String, dynamic> toJson() => {'id': id, 'category': category, 'subCategory': subCategory, 'text': text, 'options': options, 'correctAnswerIndex': correctAnswerIndex};
}

class TestSession {
  final String category;
  final String subCategory;
  final int score;
  final int totalQuestions;
  final int durationSeconds;
  final int timestamp;
  final List<Question> questions;
  final Map<String, int> userAnswers; // Question ID -> Selected Option
  final Map<String, int> timePerQuestion; // Question ID -> Seconds Spent

  TestSession({required this.category, required this.subCategory, required this.score, required this.totalQuestions, required this.durationSeconds, required this.timestamp, required this.questions, required this.userAnswers, required this.timePerQuestion});

  factory TestSession.fromJson(Map<String, dynamic> json) => TestSession(
        category: json['category'] ?? '',
        subCategory: json['subCategory'] ?? '',
        score: json['score'] ?? 0,
        totalQuestions: json['totalQuestions'] ?? 0,
        durationSeconds: json['durationSeconds'] ?? 0,
        timestamp: json['timestamp'] ?? 0,
        questions: (json['questions'] as List<dynamic>?)?.map((q) => Question.fromJson(q)).toList() ??[],
        userAnswers: Map<String, int>.from(json['userAnswers'] ?? {}),
        timePerQuestion: Map<String, int>.from(json['timePerQuestion'] ?? {}),
      );

  Map<String, dynamic> toJson() => {'category': category, 'subCategory': subCategory, 'score': score, 'totalQuestions': totalQuestions, 'durationSeconds': durationSeconds, 'timestamp': timestamp, 'questions': questions.map((q) => q.toJson()).toList(), 'userAnswers': userAnswers, 'timePerQuestion': timePerQuestion};
}

// State for active, unfinished tests (Cache)
class ActiveTestState {
  final Map<String, int> answers; // Q-ID -> option
  final Map<String, int> times; // Q-ID -> seconds
  final Map<String, int> statuses; // Q-ID -> status index
  final int totalElapsed;

  ActiveTestState({required this.answers, required this.times, required this.statuses, required this.totalElapsed});

  factory ActiveTestState.fromJson(Map<String, dynamic> json) => ActiveTestState(
      answers: Map<String, int>.from(json['answers'] ?? {}),
      times: Map<String, int>.from(json['times'] ?? {}),
      statuses: Map<String, int>.from(json['statuses'] ?? {}),
      totalElapsed: json['totalElapsed'] ?? 0);

  Map<String, dynamic> toJson() => {'answers': answers, 'times': times, 'statuses': statuses, 'totalElapsed': totalElapsed};
}

enum QuestionStatus { notVisited, notAnswered, answered, markedForReview, answeredAndMarked }

// ==========================================
// STATE MANAGEMENT (PROVIDER)
// ==========================================
class AppState extends ChangeNotifier {
  List<Question> _questions =[];
  List<TestSession> _sessions =[];
  Map<String, ActiveTestState> _activeStates = {};
  bool _isLoading = true;

  List<Question> get questions => _questions;
  List<TestSession> get sessions => _sessions;
  bool get isLoading => _isLoading;

  Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();
    
    final qJson = prefs.getString('questions');
    if (qJson != null) _questions = (jsonDecode(qJson) as List).map((q) => Question.fromJson(q)).toList();

    final sJson = prefs.getString('sessions');
    if (sJson != null) _sessions = (jsonDecode(sJson) as List).map((s) => TestSession.fromJson(s)).toList();

    final aJson = prefs.getString('active_states');
    if (aJson != null) {
      Map<String, dynamic> decoded = jsonDecode(aJson);
      _activeStates = decoded.map((k, v) => MapEntry(k, ActiveTestState.fromJson(v)));
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('questions', jsonEncode(_questions.map((q) => q.toJson()).toList()));
    await prefs.setString('sessions', jsonEncode(_sessions.map((s) => s.toJson()).toList()));
    await prefs.setString('active_states', jsonEncode(_activeStates.map((k, v) => MapEntry(k, v.toJson()))));
  }

  Future<bool> importQuestionsFromString(String jsonString) async {
    try {
      String sanitized = jsonString.trim();
      if (sanitized.startsWith('```')) {
        List<String> lines = sanitized.split('\n');
        if (lines.isNotEmpty && lines.first.trim().startsWith('```')) lines.removeAt(0);
        if (lines.isNotEmpty && lines.last.trim() == '```') lines.removeLast();
        sanitized = lines.join('\n').trim();
      }
      if (sanitized.isEmpty) return false;

      final List<dynamic> decoded = jsonDecode(sanitized);
      final newQs = decoded.map((q) => Question.fromJson(q)).toList();
      final Map<String, Question> existingMap = {for (var q in _questions) q.id: q};
      for (var q in newQs) existingMap[q.id] = q;

      _questions = existingMap.values.toList();
      await saveData();
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  void addSession(TestSession session) {
    _sessions.add(session);
    clearActiveState(session.category, session.subCategory);
    saveData();
    notifyListeners();
  }

  // Active State Management
  String _stateKey(String cat, String subCat) => "${cat}_$subCat";

  void saveActiveState(String cat, String subCat, Map<String, int> ans, Map<String, int> times, Map<String, int> statuses, int elapsed) {
    _activeStates[_stateKey(cat, subCat)] = ActiveTestState(answers: ans, times: times, statuses: statuses, totalElapsed: elapsed);
    saveData();
  }

  ActiveTestState? getActiveState(String cat, String subCat) => _activeStates[_stateKey(cat, subCat)];

  void clearActiveState(String cat, String subCat) {
    _activeStates.remove(_stateKey(cat, subCat));
    saveData();
  }

  bool isCompleted(String cat, String subCat) {
    return _sessions.any((s) => s.category == cat && s.subCategory == subCat);
  }

  // Organization
  List<String> getCategories() => _questions.map((q) => q.category).toSet().toList()..sort();
  List<String> getSubCategories(String category) => _questions.where((q) => q.category == category).map((q) => q.subCategory).toSet().toList()..sort();
  List<Question> getQuestionsBySubCategory(String category, String subCategory) => _questions.where((q) => q.category == category && q.subCategory == subCategory).toList();
  void deleteCategory(String cat) { _questions.removeWhere((q) => q.category == cat); saveData(); notifyListeners(); }
  void deleteSubCategory(String cat, String subCat) { _questions.removeWhere((q) => q.category == cat && q.subCategory == subCat); saveData(); notifyListeners(); }
  void deleteQuestion(String id) { _questions.removeWhere((q) => q.id == id); saveData(); notifyListeners(); }
  void updateQuestion(Question updatedQ) {
    int idx = _questions.indexWhere((q) => q.id == updatedQ.id);
    if (idx != -1) { _questions[idx] = updatedQ; saveData(); notifyListeners(); }
  }
}

// ==========================================
// MAIN NAVIGATION
// ==========================================
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});
  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final List<Widget> _screens = const [HomeScreen(), OrganizeScreen(), ImportScreen(), GlobalAnalysisScreen()];
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: inkBlack, width: 3))),
        child: NavigationBar(
          backgroundColor: paperBg,
          indicatorColor: brassAccent.withOpacity(0.5),
          selectedIndex: _currentIndex,
          onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
          destinations: const[
            NavigationDestination(icon: Icon(Icons.description_outlined), label: 'Tests'),
            NavigationDestination(icon: Icon(Icons.folder_special_outlined), label: 'Organize'),
            NavigationDestination(icon: Icon(Icons.input), label: 'Import'),
            NavigationDestination(icon: Icon(Icons.query_stats), label: 'Analysis'),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// IMPORT SCREEN
// ==========================================
class ImportScreen extends StatelessWidget {
  const ImportScreen({super.key});

  final String templateJson = '''[
  {
    "id": "q1",
    "category": "Math",
    "subCategory": "Algebra",
    "text": "Solve: 2x = 4",
    "options":["1", "2", "3", "4"],
    "correctAnswerIndex": 1
  }
]''';

  @override
  Widget build(BuildContext context) {
    final TextEditingController controller = TextEditingController();
    return Scaffold(
      appBar: AppBar(title: const Text('IMPORT_DATA')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children:[
            Container(
              decoration: BoxDecoration(border: Border.all(color: inkBlack, width: 2), color: brassAccent.withOpacity(0.2)),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children:[
                  const Text('REFERENCE_JSON_STRUCTURE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(templateJson, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: templateJson));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard'), backgroundColor: Colors.black));
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('COPY TEMPLATE'),
                  )
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: controller,
              maxLines: 12,
              decoration: const InputDecoration(hintText: 'PASTE_JSON_HERE...', labelText: 'DATA_INPUT'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                bool success = await context.read<AppState>().importQuestionsFromString(controller.text);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(success ? 'SYSTEM: IMPORT SUCCESSFUL' : 'ERROR: INVALID FORMAT'),
                    backgroundColor: success ? steamGreen : rustRed,
                    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                  ));
                  if(success) controller.clear();
                }
              },
              child: const Text('EXECUTE IMPORT'),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// HOME SCREEN (Tests)
// ==========================================
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final categories = appState.getCategories();

    return Scaffold(
      appBar: AppBar(title: const Text('INDEX: DIRECTORIES')),
      body: appState.isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.black))
          : categories.isEmpty
              ? const Center(child: Text('NO DATA FOUND. PROCEED TO IMPORT.', style: TextStyle(fontWeight: FontWeight.bold)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.folder_open, color: Colors.black),
                        title: Text(category.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.black),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SubCategoryScreen(category: category))),
                      ),
                    );
                  },
                ),
    );
  }
}

class SubCategoryScreen extends StatelessWidget {
  final String category;
  const SubCategoryScreen({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    List<String> subCats = appState.getSubCategories(category);

    // SORTING: Unfinished top, Completed bottom
    subCats.sort((a, b) {
      bool aComp = appState.isCompleted(category, a);
      bool bComp = appState.isCompleted(category, b);
      if (aComp == bComp) return a.compareTo(b);
      return aComp ? 1 : -1;
    });

    return Scaffold(
      appBar: AppBar(title: Text('DIR: ${category.toUpperCase()}')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: subCats.length,
        itemBuilder: (context, index) {
          final subCat = subCats[index];
          final questions = appState.getQuestionsBySubCategory(category, subCat);
          final isCompleted = appState.isCompleted(category, subCat);
          final hasActiveState = appState.getActiveState(category, subCat) != null;

          return Card(
            color: isCompleted ? Colors.grey.shade300 : paperBg,
            child: ListTile(
              leading: Icon(isCompleted ? Icons.check_box : Icons.insert_drive_file, color: inkBlack),
              title: Text(subCat.toUpperCase(), style: TextStyle(fontWeight: FontWeight.bold, decoration: isCompleted ? TextDecoration.lineThrough : null)),
              subtitle: Text('QS: ${questions.length} | STAT: ${isCompleted ? 'COMPLETED' : (hasActiveState ? 'IN PROGRESS' : 'UNFINISHED')}'),
              trailing: const Icon(Icons.play_arrow, color: Colors.black, size: 30),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ExamScreen(category: category, subCategory: subCat, questions: questions))),
            ),
          );
        },
      ),
    );
  }
}

// ==========================================
// EXAM SCREEN
// ==========================================
class ExamScreen extends StatefulWidget {
  final String category;
  final String subCategory;
  final List<Question> questions;
  const ExamScreen({super.key, required this.category, required this.subCategory, required this.questions});
  @override
  State<ExamScreen> createState() => _ExamScreenState();
}

class _ExamScreenState extends State<ExamScreen> {
  int _currentIndex = 0;
  final Map<String, int> _answers = {}; // Q-ID -> Option
  final Map<String, int> _times = {};   // Q-ID -> Seconds
  final Map<String, int> _statuses = {};// Q-ID -> Status enum index
  int _totalElapsed = 0;
  
  late Timer _timer;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _loadState();
    _timer = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  void _loadState() {
    final state = context.read<AppState>().getActiveState(widget.category, widget.subCategory);
    for (var q in widget.questions) {
      _times[q.id] = 0;
      _statuses[q.id] = QuestionStatus.notVisited.index;
    }
    
    if (state != null) {
      _answers.addAll(state.answers);
      _times.addAll(state.times);
      _statuses.addAll(state.statuses);
      _totalElapsed = state.totalElapsed;
      
      // Find first unanswered or not visited
      _currentIndex = widget.questions.indexWhere((q) => _statuses[q.id] == QuestionStatus.notVisited.index || _statuses[q.id] == QuestionStatus.notAnswered.index);
      if (_currentIndex == -1) _currentIndex = 0;
    }
    
    String startQId = widget.questions[_currentIndex].id;
    if (_statuses[startQId] == QuestionStatus.notVisited.index) {
      _statuses[startQId] = QuestionStatus.notAnswered.index;
    }
  }

  void _tick(Timer timer) {
    setState(() {
      _totalElapsed++;
      String qId = widget.questions[_currentIndex].id;
      _times[qId] = (_times[qId] ?? 0) + 1;
    });
  }

  void _saveState() {
    context.read<AppState>().saveActiveState(widget.category, widget.subCategory, _answers, _times, _statuses, _totalElapsed);
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _goToIndex(int index) {
    setState(() {
      String nextQId = widget.questions[index].id;
      if (_statuses[nextQId] == QuestionStatus.notVisited.index) {
        _statuses[nextQId] = QuestionStatus.notAnswered.index;
      }
      _currentIndex = index;
    });
    _saveState();
  }

  void _updateStatusAndNext(QuestionStatus newStatus) {
    setState(() {
      _statuses[widget.questions[_currentIndex].id] = newStatus.index;
      if (_currentIndex < widget.questions.length - 1) _goToIndex(_currentIndex + 1);
      else _saveState();
    });
  }

  void _submitTest() {
    _timer.cancel();
    int score = 0;
    for (var q in widget.questions) {
      if (_answers[q.id] == q.correctAnswerIndex) score++;
    }

    final session = TestSession(
      category: widget.category,
      subCategory: widget.subCategory,
      score: score,
      totalQuestions: widget.questions.length,
      durationSeconds: _totalElapsed,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      questions: widget.questions,
      userAnswers: _answers,
      timePerQuestion: _times,
    );

    context.read<AppState>().addSession(session);
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ResultScreen(session: session)));
  }

  Color _getStatusColor(int statusIdx) {
    if (statusIdx == QuestionStatus.notVisited.index) return Colors.grey.shade400;
    if (statusIdx == QuestionStatus.notAnswered.index) return rustRed;
    if (statusIdx == QuestionStatus.answered.index) return steamGreen;
    if (statusIdx == QuestionStatus.markedForReview.index) return Colors.purple;
    if (statusIdx == QuestionStatus.answeredAndMarked.index) return Colors.purple;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.questions[_currentIndex];
    final qId = question.id;
    final int minutes = _totalElapsed ~/ 60;
    final int seconds = _totalElapsed % 60;

    return WillPopScope(
      onWillPop: () async {
        _saveState();
        return true;
      },
      child: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: Text("T:${minutes.toString().padLeft(2,'0')}:${seconds.toString().padLeft(2,'0')} | Q:${_times[qId]}s"),
          actions:[
            IconButton(icon: const Icon(Icons.grid_view, color: Colors.black), onPressed: () => _scaffoldKey.currentState?.openEndDrawer())
          ],
        ),
        endDrawer: Drawer(
          child: Column(
            children:[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: inkBlack, width: 2))),
                child: const Text('PALETTE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 5, crossAxisSpacing: 8, mainAxisSpacing: 8),
                  itemCount: widget.questions.length,
                  itemBuilder: (ctx, i) {
                    int sIdx = _statuses[widget.questions[i].id] ?? 0;
                    return GestureDetector(
                      onTap: () { Navigator.pop(context); _goToIndex(i); },
                      child: Container(
                        decoration: BoxDecoration(
                          color: _getStatusColor(sIdx),
                          border: Border.all(color: _currentIndex == i ? Colors.white : inkBlack, width: _currentIndex == i ? 3 : 2),
                        ),
                        alignment: Alignment.center,
                        child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        body: Column(
          children:[
            LinearProgressIndicator(value: (_currentIndex + 1) / widget.questions.length, backgroundColor: paperBg, color: inkBlack, minHeight: 4),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children:[
                  Text('ID: $qId [${_currentIndex + 1}/${widget.questions.length}]', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
                  const Divider(height: 32),
                  MarkdownBody(data: question.text, styleSheet: MarkdownStyleSheet(p: const TextStyle(fontSize: 18, height: 1.5, fontWeight: FontWeight.bold))),
                  const SizedBox(height: 32),
                  ...List.generate(question.options.length, (optIdx) {
                    bool isSelected = _answers[qId] == optIdx;
                    return InkWell(
                      onTap: () {
                        setState(() => _answers[qId] = optIdx);
                        _saveState();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected ? brassAccent.withOpacity(0.3) : paperBg,
                          border: Border.all(color: inkBlack, width: isSelected ? 3 : 2),
                        ),
                        child: Row(
                          children: [
                            Radio<int>(value: optIdx, groupValue: _answers[qId], activeColor: inkBlack, onChanged: (v) { setState(() => _answers[qId] = v!); _saveState(); }),
                            Expanded(child: MarkdownBody(data: question.options[optIdx])),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(border: Border(top: BorderSide(color: inkBlack, width: 3)), color: paperBg),
              padding: const EdgeInsets.all(8),
              child: Column(
                children:[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children:[
                      OutlinedButton(onPressed: () { setState(() { _answers.remove(qId); _statuses[qId] = QuestionStatus.notAnswered.index; }); _saveState(); }, child: const Text('CLEAR')),
                      OutlinedButton(onPressed: () => _updateStatusAndNext(_answers.containsKey(qId) ? QuestionStatus.answeredAndMarked : QuestionStatus.markedForReview), child: const Text('MARK & NEXT')),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children:[
                      if (_currentIndex > 0) FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.grey.shade700), onPressed: () => _goToIndex(_currentIndex - 1), child: const Text('PREV')),
                      if (_currentIndex < widget.questions.length - 1)
                        FilledButton(onPressed: () => _updateStatusAndNext(_answers.containsKey(qId) ? QuestionStatus.answered : QuestionStatus.notAnswered), child: const Text('SAVE & NEXT'))
                      else
                        FilledButton(style: FilledButton.styleFrom(backgroundColor: steamGreen), onPressed: _submitTest, child: const Text('SUBMIT TEST')),
                    ],
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

// ==========================================
// RESULT & REVIEW SCREENS
// ==========================================
class ResultScreen extends StatelessWidget {
  final TestSession session;
  const ResultScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    double perc = session.totalQuestions > 0 ? (session.score / session.totalQuestions) * 100 : 0;
    return Scaffold(
      appBar: AppBar(title: const Text('EVALUATION_REPORT'), automaticallyImplyLeading: false),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children:[
              Text('STATUS: ${perc >= 70 ? 'PASS' : 'FAIL'}', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: perc >= 70 ? steamGreen : rustRed)),
              const Divider(height: 48),
              Text('SCORE: ${session.score} / ${session.totalQuestions}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              Text('ACCURACY: ${perc.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 20)),
              Text('TIME: ${session.durationSeconds}s', style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 48),
              FilledButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewScreen(session: session))), child: const Text('INITIATE REVIEW')),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), child: const Text('TERMINATE')),
            ],
          ),
        ),
      ),
    );
  }
}

enum SortMode { defaultOrder, timeAsc, timeDesc }

class ReviewScreen extends StatefulWidget {
  final TestSession session;
  const ReviewScreen({super.key, required this.session});
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  SortMode _sortMode = SortMode.defaultOrder;

  @override
  Widget build(BuildContext context) {
    List<Question> sortedQs = List.from(widget.session.questions);

    sortedQs.sort((a, b) {
      if (_sortMode == SortMode.timeAsc) {
        return (widget.session.timePerQuestion[a.id] ?? 0).compareTo(widget.session.timePerQuestion[b.id] ?? 0);
      } else if (_sortMode == SortMode.timeDesc) {
        return (widget.session.timePerQuestion[b.id] ?? 0).compareTo(widget.session.timePerQuestion[a.id] ?? 0);
      } else {
        // Default: Wrong -> Not Answered -> Correct
        bool aCorrect = widget.session.userAnswers[a.id] == a.correctAnswerIndex;
        bool bCorrect = widget.session.userAnswers[b.id] == b.correctAnswerIndex;
        bool aAns = widget.session.userAnswers.containsKey(a.id);
        bool bAns = widget.session.userAnswers.containsKey(b.id);
        
        int score(bool isCor, bool isAns) => isCor ? 2 : (!isAns ? 1 : 0); // 0=Wrong, 1=Unanswered, 2=Correct
        return score(aCorrect, aAns).compareTo(score(bCorrect, bAns));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('ANALYSIS_MATRIX')),
      body: Column(
        children:[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: inkBlack, width: 2))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children:[
                const Text('SORT_OPTS:', style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<SortMode>(
                  value: _sortMode,
                  dropdownColor: paperBg,
                  underline: const SizedBox(),
                  style: TextStyle(fontFamily: 'Courier', color: inkBlack, fontWeight: FontWeight.bold),
                  items: const[
                    DropdownMenuItem(value: SortMode.defaultOrder, child: Text('ERRORS_FIRST')),
                    DropdownMenuItem(value: SortMode.timeAsc, child: Text('TIME_ASC (FAST)')),
                    DropdownMenuItem(value: SortMode.timeDesc, child: Text('TIME_DESC (SLOW)')),
                  ],
                  onChanged: (v) => setState(() => _sortMode = v!),
                )
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sortedQs.length,
              itemBuilder: (ctx, i) {
                final q = sortedQs[i];
                final uAns = widget.session.userAnswers[q.id];
                final isCorrect = uAns == q.correctAnswerIndex;
                final timeS = widget.session.timePerQuestion[q.id] ?? 0;

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(isCorrect ? '[VALID]' : (uAns == null ? '[NULL]' : '[ERROR]'), style: TextStyle(color: isCorrect ? steamGreen : rustRed, fontWeight: FontWeight.bold, fontSize: 18)),
                            Text('TIME: ${timeS}s', style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const Divider(height: 24),
                        MarkdownBody(data: q.text),
                        const SizedBox(height: 16),
                        ...List.generate(q.options.length, (optIdx) {
                          bool correctOpt = optIdx == q.correctAnswerIndex;
                          bool selectedOpt = optIdx == uAns;
                          Color bg = paperBg;
                          if (correctOpt) bg = steamGreen.withOpacity(0.3);
                          else if (selectedOpt && !correctOpt) bg = rustRed.withOpacity(0.3);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: bg, border: Border.all(color: inkBlack, width: correctOpt || selectedOpt ? 2 : 1)),
                            child: Row(
                              children:[
                                if (correctOpt) const Icon(Icons.check, color: Colors.black) else if (selectedOpt) const Icon(Icons.close, color: Colors.black) else const SizedBox(width: 24),
                                const SizedBox(width: 8),
                                Expanded(child: MarkdownBody(data: q.options[optIdx])),
                              ],
                            ),
                          );
                        })
                      ],
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

// ==========================================
// GLOBAL ANALYSIS
// ==========================================
class GlobalAnalysisScreen extends StatefulWidget {
  const GlobalAnalysisScreen({super.key});
  @override
  State<GlobalAnalysisScreen> createState() => _GlobalAnalysisScreenState();
}

class _GlobalAnalysisScreenState extends State<GlobalAnalysisScreen> {
  SortMode _sortMode = SortMode.timeDesc;

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<AppState>().sessions;

    if (sessions.isEmpty) return Scaffold(appBar: AppBar(title: const Text('GLOBAL_SYS_STATS')), body: const Center(child: Text('NO DATA', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))));

    // Aggregate all answered questions
    List<Map<String, dynamic>> allRecords =[];
    for (var s in sessions) {
      for (var q in s.questions) {
        int time = s.timePerQuestion[q.id] ?? 0;
        bool isCorrect = s.userAnswers[q.id] == q.correctAnswerIndex;
        bool isAns = s.userAnswers.containsKey(q.id);
        allRecords.add({'q': q, 'time': time, 'isCorrect': isCorrect, 'isAns': isAns, 'sessionCat': s.category});
      }
    }

    allRecords.sort((a, b) {
      if (_sortMode == SortMode.timeAsc) return (a['time'] as int).compareTo(b['time'] as int);
      if (_sortMode == SortMode.timeDesc) return (b['time'] as int).compareTo(a['time'] as int);
      return (a['isCorrect'] ? 2 : (!a['isAns'] ? 1 : 0)).compareTo(b['isCorrect'] ? 2 : (!b['isAns'] ? 1 : 0));
    });

    return Scaffold(
      appBar: AppBar(title: const Text('GLOBAL_SYS_STATS')),
      body: Column(
        children:[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: inkBlack, width: 2))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children:[
                const Text('SORT_ALL_QS:', style: TextStyle(fontWeight: FontWeight.bold)),
                DropdownButton<SortMode>(
                  value: _sortMode,
                  dropdownColor: paperBg,
                  underline: const SizedBox(),
                  style: TextStyle(fontFamily: 'Courier', color: inkBlack, fontWeight: FontWeight.bold),
                  items: const[
                    DropdownMenuItem(value: SortMode.defaultOrder, child: Text('ERRORS_FIRST')),
                    DropdownMenuItem(value: SortMode.timeAsc, child: Text('FASTEST_FIRST')),
                    DropdownMenuItem(value: SortMode.timeDesc, child: Text('SLOWEST_FIRST')),
                  ],
                  onChanged: (v) => setState(() => _sortMode = v!),
                )
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: allRecords.length,
              itemBuilder: (ctx, i) {
                final rec = allRecords[i];
                final Question q = rec['q'];
                return Card(
                  child: ListTile(
                    leading: Text('${rec['time']}s', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    title: Text(q.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('DIR: ${rec['sessionCat']}'),
                    trailing: Icon(rec['isCorrect'] ? Icons.check_box : Icons.cancel_presentation, color: rec['isCorrect'] ? steamGreen : rustRed),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

// ==========================================
// ORGANIZE SCREEN
// ==========================================
class OrganizeScreen extends StatelessWidget {
  const OrganizeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final categories = appState.getCategories();

    return Scaffold(
      appBar: AppBar(title: const Text('SYS_ORGANIZATION')),
      body: categories.isEmpty
          ? const Center(child: Text('EMPTY_DATABASE', style: TextStyle(fontWeight: FontWeight.bold)))
          : ListView.builder(
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final cat = categories[index];
                return Container(
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: inkBlack, width: 2))),
                  child: ExpansionTile(
                    title: Text(cat.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
                    trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.black), onPressed: () => appState.deleteCategory(cat)),
                    children: appState.getSubCategories(cat).map((subCat) {
                      return Container(
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: inkBlack, width: 1)), color: brassAccent.withOpacity(0.1)),
                        child: ExpansionTile(
                          title: Text(' > ${subCat.toUpperCase()}'),
                          trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.black), onPressed: () => appState.deleteSubCategory(cat, subCat)),
                          children: appState.getQuestionsBySubCategory(cat, subCat).map((q) => ListTile(
                            title: Text(q.text, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: IconButton(icon: const Icon(Icons.delete_forever, color: Colors.black), onPressed: () => appState.deleteQuestion(q.id)),
                          )).toList(),
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
    );
  }
}
