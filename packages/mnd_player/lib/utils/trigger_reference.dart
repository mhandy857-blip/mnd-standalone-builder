class TriggerReference {
  final String scriptPath;
  final String? functionEntry;

  const TriggerReference({required this.scriptPath, this.functionEntry});

  bool get isFunctionRef => functionEntry != null && functionEntry!.isNotEmpty;

  String serialize() {
    if (!isFunctionRef) return scriptPath;
    final encoded = Uri.encodeComponent(functionEntry!);
    return '$scriptPath#fn=$encoded';
  }

  static TriggerReference parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      return const TriggerReference(scriptPath: '');
    }

    final fnIndex = text.indexOf('#fn=');
    if (fnIndex == -1) {
      return TriggerReference(scriptPath: text);
    }

    final scriptPart = text.substring(0, fnIndex).trim();
    final fnPartRaw = text.substring(fnIndex + 4).trim();
    if (fnPartRaw.isEmpty) {
      return TriggerReference(scriptPath: scriptPart);
    }
    final fnPart = Uri.decodeComponent(fnPartRaw);
    return TriggerReference(scriptPath: scriptPart, functionEntry: fnPart);
  }
}
