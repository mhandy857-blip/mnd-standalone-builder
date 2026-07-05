import 'dart:convert';

import 'package:mnd_core/mnd_core.dart';
import 'package:crypto/crypto.dart';

class TemplateInstanceResolver {
  final Map<String, TemplateItem> templatesById;

  final Map<_ResolveKey, ContentItem> _contentCache = {};
  final Map<_ResolveKey, SavedNode> _nodeCache = {};

  TemplateInstanceResolver({required this.templatesById});

  void clearCache() {
    _contentCache.clear();
    _nodeCache.clear();
  }

  void invalidateTemplate(String templateId) {
    _contentCache.removeWhere((k, _) => k.templateId == templateId);
    _nodeCache.removeWhere((k, _) => k.templateId == templateId);
  }

  ContentItem resolveContentItem(ContentItem instance) {
    if (!instance.isTemplateInstance) return instance;
    final master = templatesById[instance.templateRef];
    if (master == null) return instance;

    final key = _ResolveKey(
      instanceId: instance.id,
      templateId: master.id,
      version: master.contentVersion,
    );
    final cached = _contentCache[key];
    if (cached != null) return _mergeTopLevel(cached, instance);

    final masterItem = _parseContentFromPayload(master.payload);
    if (masterItem == null) return instance;

    final expanded = _expandContentItem(
      master: masterItem,
      instanceId: instance.id,
      seedPath: '\$',
    );
    _contentCache[key] = expanded;
    return _mergeTopLevel(expanded, instance);
  }

  ResolvedContentItem tryResolveContentItem(ContentItem instance) {
    if (!instance.isTemplateInstance) {
      return ResolvedContentItem(item: instance, missingTemplate: false);
    }
    final master = templatesById[instance.templateRef];
    if (master == null) {
      return ResolvedContentItem(item: instance, missingTemplate: true);
    }
    return ResolvedContentItem(
      item: resolveContentItem(instance),
      missingTemplate: false,
      masterVersion: master.contentVersion,
      masterName: master.name,
    );
  }

  ContentItem resolveTree(ContentItem item, {Set<String>? visited}) {
    final visitedSet = visited ?? <String>{};
    if (item.isTemplateInstance) {
      final ref = item.templateRef!;
      if (visitedSet.contains(ref)) {
        return item;
      }
      visitedSet.add(ref);
      final expanded = resolveContentItem(item);
      final children = expanded.children;
      if (children == null || children.isEmpty) return expanded;
      return expanded.copyWith(
        children: children
            .map((c) => resolveTree(c, visited: visitedSet))
            .toList(),
      );
    }
    final children = item.children;
    if (children == null || children.isEmpty) return item;
    return item.copyWith(
      children: children
          .map((c) => resolveTree(c, visited: visitedSet))
          .toList(),
    );
  }

  List<ContentItem> resolveList(List<ContentItem> items) {
    return items.map(resolveTree).toList();
  }

  SavedNode resolveNode(SavedNode instance) {
    if (!instance.isTemplateInstance) return instance;
    final master = templatesById[instance.templateRef];
    if (master == null) return instance;

    final key = _ResolveKey(
      instanceId: instance.id,
      templateId: master.id,
      version: master.contentVersion,
    );
    final cached = _nodeCache[key];
    if (cached != null) return _mergeNodeTopLevel(cached, instance);

    final masterNode = _parseNodeFromPayload(master.payload);
    if (masterNode == null) return instance;

    final fixedContent = _expandContentMap(
      content: masterNode.content,
      instanceId: instance.id,
    );
    final expanded = SavedNode(
      id: instance.id,
      chapterId: instance.chapterId,
      title: masterNode.title,
      content: fixedContent,
      x: instance.x,
      y: instance.y,
      color: masterNode.color,
      backgroundAssetId: masterNode.backgroundAssetId,
      scriptAssetId: masterNode.scriptAssetId,
      timerDuration: masterNode.timerDuration,
      defaultActionNodeId: null,
      backgroundAudioId: masterNode.backgroundAudioId,
      backgroundAudioVolume: masterNode.backgroundAudioVolume,
      templateRef: instance.templateRef,
      templateVersion: master.contentVersion,
    );
    _nodeCache[key] = expanded;
    return _mergeNodeTopLevel(expanded, instance);
  }

  ResolvedNode tryResolveNode(SavedNode instance) {
    if (!instance.isTemplateInstance) {
      return ResolvedNode(node: instance, missingTemplate: false);
    }
    final master = templatesById[instance.templateRef];
    if (master == null) {
      return ResolvedNode(node: instance, missingTemplate: true);
    }
    return ResolvedNode(
      node: resolveNode(instance),
      missingTemplate: false,
      masterVersion: master.contentVersion,
      masterName: master.name,
    );
  }

  ContentItem? _parseContentFromPayload(Map<String, dynamic> payload) {
    try {
      return ContentItem.fromJson(_deepClone(payload));
    } catch (_) {
      return null;
    }
  }

  SavedNode? _parseNodeFromPayload(Map<String, dynamic> payload) {
    try {
      return SavedNode.fromJson(_deepClone(payload));
    } catch (_) {
      return null;
    }
  }

  ContentItem _expandContentItem({
    required ContentItem master,
    required String instanceId,
    required String seedPath,
  }) {
    final children = master.children;
    final List<ContentItem>? newChildren = children == null
        ? null
        : List.generate(
            children.length,
            (i) => _expandContentItem(
              master: children[i],
              instanceId: instanceId,
              seedPath: '$seedPath.children[$i]',
            ),
          );
    final newModalButtons = master.modalButtons == null
        ? null
        : List.generate(master.modalButtons!.length, (i) {
            final b = master.modalButtons![i];
            return b.copyWith(
              id: _deriveId(instanceId, '$seedPath.modalButtons[$i]'),
            );
          });

    return master.copyWith(
      id: _deriveId(instanceId, seedPath),
      children: newChildren,
      modalButtons: newModalButtons,
    );
  }

  Map<String, dynamic> _expandContentMap({
    required Map<String, dynamic> content,
    required String instanceId,
  }) {
    final items = content['items'];
    if (items is! List) return content;
    final fixed = <Map<String, dynamic>>[];
    for (var i = 0; i < items.length; i++) {
      final raw = items[i];
      if (raw is Map) {
        try {
          final ci = ContentItem.fromJson(Map<String, dynamic>.from(raw));
          final exp = _expandContentItem(
            master: ci,
            instanceId: instanceId,
            seedPath: '\$.items[$i]',
          );
          fixed.add(exp.toJson());
        } catch (_) {
          final m = Map<String, dynamic>.from(raw);
          m['id'] = _deriveId(instanceId, '\$.items[$i]');
          fixed.add(m);
        }
      }
    }
    return {...content, 'items': fixed};
  }

  ContentItem _mergeTopLevel(ContentItem master, ContentItem instance) {
    return master.copyWith(
      id: instance.id,
      flex: instance.flex,
      isHidden: instance.isHidden,
      backgroundColor: instance.backgroundColor,
      templateRef: instance.templateRef,
      templateVersion: master.templateVersion ?? instance.templateVersion,
    );
  }

  SavedNode _mergeNodeTopLevel(SavedNode master, SavedNode instance) {
    return SavedNode(
      id: instance.id,
      chapterId: instance.chapterId,
      title: master.title,
      content: master.content,
      x: instance.x,
      y: instance.y,
      color: master.color,
      backgroundAssetId: master.backgroundAssetId,
      scriptAssetId: master.scriptAssetId,
      timerDuration: master.timerDuration,
      defaultActionNodeId: null,
      backgroundAudioId: master.backgroundAudioId,
      backgroundAudioVolume: master.backgroundAudioVolume,
      templateRef: instance.templateRef,
      templateVersion: master.templateVersion ?? instance.templateVersion,
    );
  }

  String _deriveId(String instanceId, String path) {
    final raw = '$instanceId|$path';
    final h = sha1.convert(utf8.encode(raw)).toString();
    return 'tpl_${h.substring(0, 16)}';
  }

  Map<String, dynamic> _deepClone(Map<String, dynamic> source) {
    final encoded = jsonEncode(source);
    final decoded = jsonDecode(encoded);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return <String, dynamic>{};
  }
}

class ResolvedContentItem {
  final ContentItem item;
  final bool missingTemplate;
  final int? masterVersion;
  final String? masterName;
  const ResolvedContentItem({
    required this.item,
    required this.missingTemplate,
    this.masterVersion,
    this.masterName,
  });
}

class ResolvedNode {
  final SavedNode node;
  final bool missingTemplate;
  final int? masterVersion;
  final String? masterName;
  const ResolvedNode({
    required this.node,
    required this.missingTemplate,
    this.masterVersion,
    this.masterName,
  });
}

class _ResolveKey {
  final String instanceId;
  final String templateId;
  final int version;
  const _ResolveKey({
    required this.instanceId,
    required this.templateId,
    required this.version,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _ResolveKey &&
          other.instanceId == instanceId &&
          other.templateId == templateId &&
          other.version == version);

  @override
  int get hashCode => Object.hash(instanceId, templateId, version);
}
