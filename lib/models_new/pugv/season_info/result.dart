import 'package:PiliPlus/models_new/pugv/season_info/brief.dart';
import 'package:PiliPlus/models_new/pugv/season_info/cooperator.dart';
import 'package:PiliPlus/models_new/pugv/season_info/episode.dart';
import 'package:PiliPlus/models_new/pugv/season_info/new_ep.dart';
import 'package:PiliPlus/models_new/pugv/season_info/stat.dart';
import 'package:PiliPlus/models_new/pugv/season_info/up_info.dart';
import 'package:PiliPlus/models_new/pugv/season_info/user_status.dart';

class SeasonInfoModel {
  String? cover;
  List<EpisodeItem>? episodes;
  NewEp? newEp;
  int? seasonId;
  String? seasonTitle;
  SeasonStat? stat;
  String? subtitle;
  String? title;
  UpInfo? upInfo;
  UserStatus? userStatus;
  List<Cooperator>? cooperators;
  Brief? brief;

  SeasonInfoModel({
    this.cover,
    this.episodes,
    this.newEp,
    this.seasonId,
    this.seasonTitle,
    this.stat,
    this.subtitle,
    this.title,
    this.upInfo,
    this.userStatus,
    this.cooperators,
    this.brief,
  });

  factory SeasonInfoModel.fromJson(Map<String, dynamic> json) =>
      SeasonInfoModel(
        cover: json['cover'] as String?,
        episodes: (json['episodes'] as List<dynamic>?)
            ?.map((e) => EpisodeItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        newEp: json['new_ep'] == null
            ? null
            : NewEp.fromJson(json['new_ep'] as Map<String, dynamic>),
        seasonId: json['season_id'] as int?,
        seasonTitle: json['season_title'] as String?,
        stat: json['stat'] == null
            ? null
            : SeasonStat.fromJson(json['stat'] as Map<String, dynamic>),
        subtitle: json['subtitle'] as String?,
        title: json['title'] as String?,
        upInfo: json['up_info'] == null
            ? null
            : UpInfo.fromJson(json['up_info'] as Map<String, dynamic>),
        userStatus: json['user_status'] == null
            ? null
            : UserStatus.fromJson(json['user_status'] as Map<String, dynamic>),
        cooperators: (json['cooperators'] as List?)
            ?.map((e) => Cooperator.fromJson(e))
            .toList(),
        brief: json['brief'] == null
            ? null
            : Brief.fromJson(json['brief'] as Map<String, dynamic>),
      );
}
