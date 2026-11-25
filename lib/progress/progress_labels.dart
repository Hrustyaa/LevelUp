import '../focus_experience/focus_style.dart';

String progressDate(DateTime date, {bool includeYear = true}) {
  final local = date.toLocal();
  final day = _twoDigits(local.day);
  final month = _twoDigits(local.month);
  return includeYear ? '$day.$month.${local.year}' : '$day.$month';
}

String progressTime(DateTime date) {
  final local = date.toLocal();
  return '${_twoDigits(local.hour)}:${_twoDigits(local.minute)}';
}

String progressDuration(Duration duration, String language) {
  final seconds = duration.inSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds ~/ 60) % 60;
  final remainder = seconds % 60;
  final hour = focusTr(language, 'ч', 'h', 'сағ');
  final minute = focusTr(language, 'мин', 'min', 'мин');
  final second = focusTr(language, 'с', 'sec', 'сек');
  if (seconds == 0 && duration > Duration.zero) return '<1 $second';
  return [
    if (hours > 0) '$hours $hour',
    if (minutes > 0) '$minutes $minute',
    if (remainder > 0 || seconds == 0) '$remainder $second',
  ].join(' ');
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');
