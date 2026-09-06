import 'package:PiliPlus/models/common/video/video_quality.dart';
import 'package:PiliPlus/models/video/play/url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('supplement missing qualities and deduplicate by quality and codec', () {
    VideoItem video(int id, int codec) => VideoItem(
      id: id,
      codecid: codec,
      quality: VideoQuality.fromCode(id),
    );
    final videos = [video(120, 7), video(32, 7)];
    final model = PlayUrlModel(
      dash: Dash(video: videos),
      acceptQuality: [120, 80, 32],
      supportFormats: [120, 80, 32].map((q) => FormatItem(quality: q)).toList(),
    );
    expect(model.missingVideoQualityBelowHighest, 80);
    videos.merge([video(80, 7), video(80, 7), video(80, 12)]);
    expect(videos.map((v) => (v.id, v.codecid)), [
      (120, 7),
      (80, 7),
      (80, 12),
      (32, 7),
    ]);
    expect(model.missingVideoQualityBelowHighest, -1);
    expect(model.findAvailableVideoQuality(80), 80);
    expect(model.findAvailableVideoQuality(125), 120);
    expect(PlayUrlModel().missingVideoQualityBelowHighest, -1);
  });
}
