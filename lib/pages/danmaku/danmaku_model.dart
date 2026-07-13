sealed class DanmakuExtra {
  Object get mid;
  Object get id;

  const DanmakuExtra();
}

class VideoDanmaku extends DanmakuExtra {
  @override
  final int id;
  @override
  final String mid;

  int like;

  bool isLike;

  VideoDanmaku({
    required this.id,
    required this.mid,
    this.like = 0,
    this.isLike = false,
  });
}
