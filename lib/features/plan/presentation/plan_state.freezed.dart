// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'plan_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PlanState {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlanState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PlanState()';
}


}

/// @nodoc
class $PlanStateCopyWith<$Res>  {
$PlanStateCopyWith(PlanState _, $Res Function(PlanState) __);
}


/// Adds pattern-matching-related methods to [PlanState].
extension PlanStatePatterns on PlanState {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PlanLoading value)?  loading,TResult Function( PlanReady value)?  ready,TResult Function( PlanCheckingOut value)?  checkingOut,TResult Function( PlanAwaitingReturn value)?  awaitingReturn,TResult Function( PlanConfirming value)?  confirming,TResult Function( PlanUnavailable value)?  unavailable,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PlanLoading() when loading != null:
return loading(_that);case PlanReady() when ready != null:
return ready(_that);case PlanCheckingOut() when checkingOut != null:
return checkingOut(_that);case PlanAwaitingReturn() when awaitingReturn != null:
return awaitingReturn(_that);case PlanConfirming() when confirming != null:
return confirming(_that);case PlanUnavailable() when unavailable != null:
return unavailable(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PlanLoading value)  loading,required TResult Function( PlanReady value)  ready,required TResult Function( PlanCheckingOut value)  checkingOut,required TResult Function( PlanAwaitingReturn value)  awaitingReturn,required TResult Function( PlanConfirming value)  confirming,required TResult Function( PlanUnavailable value)  unavailable,}){
final _that = this;
switch (_that) {
case PlanLoading():
return loading(_that);case PlanReady():
return ready(_that);case PlanCheckingOut():
return checkingOut(_that);case PlanAwaitingReturn():
return awaitingReturn(_that);case PlanConfirming():
return confirming(_that);case PlanUnavailable():
return unavailable(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PlanLoading value)?  loading,TResult? Function( PlanReady value)?  ready,TResult? Function( PlanCheckingOut value)?  checkingOut,TResult? Function( PlanAwaitingReturn value)?  awaitingReturn,TResult? Function( PlanConfirming value)?  confirming,TResult? Function( PlanUnavailable value)?  unavailable,}){
final _that = this;
switch (_that) {
case PlanLoading() when loading != null:
return loading(_that);case PlanReady() when ready != null:
return ready(_that);case PlanCheckingOut() when checkingOut != null:
return checkingOut(_that);case PlanAwaitingReturn() when awaitingReturn != null:
return awaitingReturn(_that);case PlanConfirming() when confirming != null:
return confirming(_that);case PlanUnavailable() when unavailable != null:
return unavailable(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  loading,TResult Function( PlanStatus status,  bool ownKey,  bool stale,  PlanNotice? notice)?  ready,TResult Function()?  checkingOut,TResult Function()?  awaitingReturn,TResult Function( int elapsedSeconds)?  confirming,TResult Function()?  unavailable,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PlanLoading() when loading != null:
return loading();case PlanReady() when ready != null:
return ready(_that.status,_that.ownKey,_that.stale,_that.notice);case PlanCheckingOut() when checkingOut != null:
return checkingOut();case PlanAwaitingReturn() when awaitingReturn != null:
return awaitingReturn();case PlanConfirming() when confirming != null:
return confirming(_that.elapsedSeconds);case PlanUnavailable() when unavailable != null:
return unavailable();case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  loading,required TResult Function( PlanStatus status,  bool ownKey,  bool stale,  PlanNotice? notice)  ready,required TResult Function()  checkingOut,required TResult Function()  awaitingReturn,required TResult Function( int elapsedSeconds)  confirming,required TResult Function()  unavailable,}) {final _that = this;
switch (_that) {
case PlanLoading():
return loading();case PlanReady():
return ready(_that.status,_that.ownKey,_that.stale,_that.notice);case PlanCheckingOut():
return checkingOut();case PlanAwaitingReturn():
return awaitingReturn();case PlanConfirming():
return confirming(_that.elapsedSeconds);case PlanUnavailable():
return unavailable();}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  loading,TResult? Function( PlanStatus status,  bool ownKey,  bool stale,  PlanNotice? notice)?  ready,TResult? Function()?  checkingOut,TResult? Function()?  awaitingReturn,TResult? Function( int elapsedSeconds)?  confirming,TResult? Function()?  unavailable,}) {final _that = this;
switch (_that) {
case PlanLoading() when loading != null:
return loading();case PlanReady() when ready != null:
return ready(_that.status,_that.ownKey,_that.stale,_that.notice);case PlanCheckingOut() when checkingOut != null:
return checkingOut();case PlanAwaitingReturn() when awaitingReturn != null:
return awaitingReturn();case PlanConfirming() when confirming != null:
return confirming(_that.elapsedSeconds);case PlanUnavailable() when unavailable != null:
return unavailable();case _:
  return null;

}
}

}

/// @nodoc


class PlanLoading implements PlanState {
  const PlanLoading();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlanLoading);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PlanState.loading()';
}


}




/// @nodoc


class PlanReady implements PlanState {
  const PlanReady({required this.status, required this.ownKey, required this.stale, this.notice});
  

 final  PlanStatus status;
 final  bool ownKey;
 final  bool stale;
 final  PlanNotice? notice;

/// Create a copy of PlanState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlanReadyCopyWith<PlanReady> get copyWith => _$PlanReadyCopyWithImpl<PlanReady>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlanReady&&(identical(other.status, status) || other.status == status)&&(identical(other.ownKey, ownKey) || other.ownKey == ownKey)&&(identical(other.stale, stale) || other.stale == stale)&&(identical(other.notice, notice) || other.notice == notice));
}


@override
int get hashCode => Object.hash(runtimeType,status,ownKey,stale,notice);

@override
String toString() {
  return 'PlanState.ready(status: $status, ownKey: $ownKey, stale: $stale, notice: $notice)';
}


}

/// @nodoc
abstract mixin class $PlanReadyCopyWith<$Res> implements $PlanStateCopyWith<$Res> {
  factory $PlanReadyCopyWith(PlanReady value, $Res Function(PlanReady) _then) = _$PlanReadyCopyWithImpl;
@useResult
$Res call({
 PlanStatus status, bool ownKey, bool stale, PlanNotice? notice
});




}
/// @nodoc
class _$PlanReadyCopyWithImpl<$Res>
    implements $PlanReadyCopyWith<$Res> {
  _$PlanReadyCopyWithImpl(this._self, this._then);

  final PlanReady _self;
  final $Res Function(PlanReady) _then;

/// Create a copy of PlanState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? status = null,Object? ownKey = null,Object? stale = null,Object? notice = freezed,}) {
  return _then(PlanReady(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as PlanStatus,ownKey: null == ownKey ? _self.ownKey : ownKey // ignore: cast_nullable_to_non_nullable
as bool,stale: null == stale ? _self.stale : stale // ignore: cast_nullable_to_non_nullable
as bool,notice: freezed == notice ? _self.notice : notice // ignore: cast_nullable_to_non_nullable
as PlanNotice?,
  ));
}


}

/// @nodoc


class PlanCheckingOut implements PlanState {
  const PlanCheckingOut();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlanCheckingOut);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PlanState.checkingOut()';
}


}




/// @nodoc


class PlanAwaitingReturn implements PlanState {
  const PlanAwaitingReturn();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlanAwaitingReturn);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PlanState.awaitingReturn()';
}


}




/// @nodoc


class PlanConfirming implements PlanState {
  const PlanConfirming({required this.elapsedSeconds});
  

 final  int elapsedSeconds;

/// Create a copy of PlanState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlanConfirmingCopyWith<PlanConfirming> get copyWith => _$PlanConfirmingCopyWithImpl<PlanConfirming>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlanConfirming&&(identical(other.elapsedSeconds, elapsedSeconds) || other.elapsedSeconds == elapsedSeconds));
}


@override
int get hashCode => Object.hash(runtimeType,elapsedSeconds);

@override
String toString() {
  return 'PlanState.confirming(elapsedSeconds: $elapsedSeconds)';
}


}

/// @nodoc
abstract mixin class $PlanConfirmingCopyWith<$Res> implements $PlanStateCopyWith<$Res> {
  factory $PlanConfirmingCopyWith(PlanConfirming value, $Res Function(PlanConfirming) _then) = _$PlanConfirmingCopyWithImpl;
@useResult
$Res call({
 int elapsedSeconds
});




}
/// @nodoc
class _$PlanConfirmingCopyWithImpl<$Res>
    implements $PlanConfirmingCopyWith<$Res> {
  _$PlanConfirmingCopyWithImpl(this._self, this._then);

  final PlanConfirming _self;
  final $Res Function(PlanConfirming) _then;

/// Create a copy of PlanState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? elapsedSeconds = null,}) {
  return _then(PlanConfirming(
elapsedSeconds: null == elapsedSeconds ? _self.elapsedSeconds : elapsedSeconds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class PlanUnavailable implements PlanState {
  const PlanUnavailable();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlanUnavailable);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'PlanState.unavailable()';
}


}




// dart format on
