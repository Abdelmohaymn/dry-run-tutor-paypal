import 'package:json_annotation/json_annotation.dart';

part 'pro_dto.g.dart';

/// `GET /v1/pro/status` → `subscription` (contracts/worker-api.md §2).
/// `status` is kept as a string: an unknown value must never crash the
/// parse (data-model.md B2), so the domain maps it, not this class.
@JsonSerializable(fieldRename: FieldRename.snake)
class ProSubscriptionDto {
  ProSubscriptionDto({required this.status, this.periodEnd, this.confirmedAt});

  factory ProSubscriptionDto.fromJson(Map<String, dynamic> json) => _$ProSubscriptionDtoFromJson(json);

  final String status;
  final String? periodEnd;
  final String? confirmedAt;

  Map<String, dynamic> toJson() => _$ProSubscriptionDtoToJson(this);
}

/// `GET /v1/pro/status` → `usage`.
@JsonSerializable(fieldRename: FieldRename.snake)
class ProUsageDto {
  ProUsageDto({
    required this.sessionsUsed,
    required this.sessionsLimit,
    required this.sessionsPeriod,
    required this.voiceSecondsUsed,
    required this.voiceSecondsLimit,
  });

  factory ProUsageDto.fromJson(Map<String, dynamic> json) => _$ProUsageDtoFromJson(json);

  final int sessionsUsed;
  final int sessionsLimit;
  final String sessionsPeriod;
  final int voiceSecondsUsed;
  final int voiceSecondsLimit;

  Map<String, dynamic> toJson() => _$ProUsageDtoToJson(this);
}

/// `GET /v1/pro/status`.
@JsonSerializable(fieldRename: FieldRename.snake)
class ProStatusDto {
  ProStatusDto({
    required this.offerEnabled,
    required this.plan,
    required this.usage,
    required this.asOf,
    this.subscription,
    this.proLimit,
  });

  factory ProStatusDto.fromJson(Map<String, dynamic> json) => _$ProStatusDtoFromJson(json);

  final bool offerEnabled;
  final String plan;
  final ProSubscriptionDto? subscription;
  final String? proLimit;
  final ProUsageDto usage;
  final String asOf;

  Map<String, dynamic> toJson() => _$ProStatusDtoToJson(this);
}

/// `POST /v1/pro/checkout`: either an `approve_url` to open, or
/// `already_active`.
@JsonSerializable(fieldRename: FieldRename.snake)
class ProCheckoutDto {
  ProCheckoutDto({this.approveUrl, this.alreadyActive = false});

  factory ProCheckoutDto.fromJson(Map<String, dynamic> json) => _$ProCheckoutDtoFromJson(json);

  final String? approveUrl;

  @JsonKey(defaultValue: false)
  final bool alreadyActive;

  Map<String, dynamic> toJson() => _$ProCheckoutDtoToJson(this);
}
