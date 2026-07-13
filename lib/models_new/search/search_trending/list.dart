class SearchTrendingItemModel {
  String? keyword;
  String? icon;
  String? recommendReason;

  SearchTrendingItemModel({
    this.keyword,
    this.icon,
    this.recommendReason,
  });

  factory SearchTrendingItemModel.fromJson(Map<String, dynamic> json) =>
      SearchTrendingItemModel(
        keyword: json['keyword'] as String?,
        icon: json['icon'] as String?,
        recommendReason: (json['recommend_reason'] as String?)?.replaceFirst(
          '·',
          ' ',
        ),
      );
}
