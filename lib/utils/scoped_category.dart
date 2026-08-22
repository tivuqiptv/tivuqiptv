import '../models/channel.dart';

const _scopeSeparator = '\u001f';

String scopeCategory(String profileId, String category) =>
    '$profileId$_scopeSeparator$category';

String categoryLabel(String category) {
  final separator = category.indexOf(_scopeSeparator);
  return separator < 0 ? category : category.substring(separator + 1);
}

String? categoryProfileId(String category) {
  final separator = category.indexOf(_scopeSeparator);
  return separator < 0 ? null : category.substring(0, separator);
}

String channelRemoteId(Channel channel) {
  final owner = channel.sourceProfileId;
  return owner == null || owner.isEmpty
      ? channel.id
      : '$owner::$_scopeSeparator${channel.id}';
}
