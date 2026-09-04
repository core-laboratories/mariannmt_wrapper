/// 字典信息
class DictionaryInfo {
  final int date;
  final String filename;
  final int size;
  final String type;
  final int wordCount;

  const DictionaryInfo({
    required this.date,
    required this.filename,
    required this.size,
    required this.type,
    required this.wordCount,
  });

  factory DictionaryInfo.fromJson(Map<String, dynamic> json) {
    return DictionaryInfo(
      date: json['date'] as int? ?? 0,
      filename: json['filename'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      type: json['type'] as String? ?? 'unknown',
      wordCount: json['word_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'filename': filename,
      'size': size,
      'type': type,
      'word_count': wordCount,
    };
  }
}

/// 字典索引
class DictionaryIndex {
  final Map<String, DictionaryInfo> dictionaries;
  final int updatedAt;
  final int version;

  const DictionaryIndex({
    required this.dictionaries,
    required this.updatedAt,
    required this.version,
  });

  factory DictionaryIndex.fromJson(Map<String, dynamic> json) {
    final dictionariesMap = <String, DictionaryInfo>{};
    if (json['dictionaries'] != null) {
      (json['dictionaries'] as Map<String, dynamic>).forEach((key, value) {
        dictionariesMap[key] =
            DictionaryInfo.fromJson(value as Map<String, dynamic>);
      });
    }
    return DictionaryIndex(
      dictionaries: dictionariesMap,
      updatedAt: json['updatedAt'] as int? ?? 0,
      version: json['version'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dictionaries':
          dictionaries.map((key, value) => MapEntry(key, value.toJson())),
      'updatedAt': updatedAt,
      'version': version,
    };
  }
}
