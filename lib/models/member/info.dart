import 'package:PiliPlus/models/model_avatar.dart';

class MemberInfoModel {
  MemberInfoModel({
    this.mid,
    this.name,
    this.sex,
    this.face,
    this.sign,
    this.level,
    this.isFollowed,
    this.topPhoto,
    this.official,
    this.vip,
    this.isSeniorMember,
  });

  int? mid;
  String? name;
  String? sex;
  String? face;
  String? sign;
  int? level;
  bool? isFollowed;
  String? topPhoto;
  BaseOfficialVerify? official;
  Vip? vip;
  int? isSeniorMember;

  MemberInfoModel.fromJson(Map<String, dynamic> json) {
    mid = json['mid'];
    name = json['name'];
    sex = json['sex'];
    face = json['face'];
    sign = json['sign'];
    level = json['level'];
    isFollowed = json['is_followed'];
    topPhoto = json['top_photo'];
    official = json['official'] == null
        ? null
        : BaseOfficialVerify.fromJson(json['official']);
    vip = Vip.fromJson(json['vip']);
    isSeniorMember = json['is_senior_member'];
  }
}
