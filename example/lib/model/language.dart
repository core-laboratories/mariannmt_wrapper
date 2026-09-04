import 'model.dart';

/// 语言代码枚举（完整版，包含所有支持的语言）
enum Language {
  albanian('sq', 'sqi', 'Albanian'),
  arabic('ar', 'ara', 'Arabic'),
  azerbaijani('az', 'aze', 'Azerbaijani'),
  bengali('bn', 'ben', 'Bengali'),
  bulgarian('bg', 'bul', 'Bulgarian'),
  catalan('ca', 'cat', 'Catalan'),
  chinese('zh', 'chi_sim', 'Chinese'),
  croatian('hr', 'hrv', 'Croatian'),
  czech('cs', 'ces', 'Czech'),
  danish('da', 'dan', 'Danish'),
  dutch('nl', 'nld', 'Dutch'),
  english('en', 'eng', 'English'),
  estonian('et', 'est', 'Estonian'),
  finnish('fi', 'fin', 'Finnish'),
  french('fr', 'fra', 'French'),
  german('de', 'deu', 'German'),
  greek('el', 'ell', 'Greek'),
  gujarati('gu', 'guj', 'Gujarati'),
  hebrew('he', 'heb', 'Hebrew'),
  hindi('hi', 'hin', 'Hindi'),
  hungarian('hu', 'hun', 'Hungarian'),
  icelandic('is', 'isl', 'Icelandic'),
  indonesian('id', 'ind', 'Indonesian'),
  italian('it', 'ita', 'Italian'),
  japanese('ja', 'jpn', 'Japanese'),
  kannada('kn', 'kan', 'Kannada'),
  korean('ko', 'kor', 'Korean'),
  latvian('lv', 'lav', 'Latvian'),
  lithuanian('lt', 'lit', 'Lithuanian'),
  malay('ms', 'msa', 'Malay'),
  malayalam('ml', 'mal', 'Malayalam'),
  persian('fa', 'fas', 'Persian'),
  polish('pl', 'pol', 'Polish'),
  portuguese('pt', 'por', 'Portuguese'),
  romanian('ro', 'ron', 'Romanian'),
  russian('ru', 'rus', 'Russian'),
  slovak('sk', 'slk', 'Slovak'),
  slovenian('sl', 'slv', 'Slovenian'),
  spanish('es', 'spa', 'Spanish'),
  swedish('sv', 'swe', 'Swedish'),
  tamil('ta', 'tam', 'Tamil'),
  telugu('te', 'tel', 'Telugu'),
  turkish('tr', 'tur', 'Turkish'),
  ukrainian('uk', 'ukr', 'Ukrainian');

  final String code;
  final String tessName;
  final String displayName;
  const Language(this.code, this.tessName, this.displayName);
}

/// 语言文件配置
class LanguageFiles {
  final String model;
  final String srcVocab;
  final String tgtVocab;
  final String lex;
  final ModelType modelType;

  const LanguageFiles({
    required this.model,
    required this.srcVocab,
    required this.tgtVocab,
    required this.lex,
    required this.modelType,
  });

  List<String> get allFiles => {model, srcVocab, tgtVocab, lex}.toList();
}
