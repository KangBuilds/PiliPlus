// ignore_for_file: constant_identifier_names
enum SearchType {
  // all('综合'),
  // 视频：video
  video('视频'),
  // 话题：topic
  // topic,
  // 用户：bili_user
  bili_user('用户'),
  // 专栏：article
  article('专栏'),
  ;
  // 相簿：photo
  // photo

  final String label;
  const SearchType(this.label);
}
