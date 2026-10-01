// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get closeButton => '닫기';

  @override
  String get logLabel => '로그';

  @override
  String get openLogFolder => '로그 폴더 열기';

  @override
  String get startupFailureTitle => '코어 시작 실패';

  @override
  String get stackTraceLabel => '스택 트레이스';

  @override
  String get startupFailureLogHint => '이번 시작의 로그(있는 경우)는 이 파일에 저장됩니다:';

  @override
  String get settingsTitle => '설정';

  @override
  String get settingsLoading => '설정 불러오는 중…';

  @override
  String get settingsAudioSection => '오디오';

  @override
  String get settingsMicrophoneLabel => '마이크';

  @override
  String get settingsSpeakerLabel => '스피커';

  @override
  String get settingsTransmissionMode => '전송 모드';

  @override
  String get settingsDeviceChangeNote => '기기를 변경하면 오디오가 즉시 다시 초기화됩니다.';

  @override
  String get settingsConnectFirst => '서버에 연결하면 마이크를 테스트할 수 있습니다.';

  @override
  String get settingsTestMicrophone => '마이크 테스트';

  @override
  String get settingsStopTest => '테스트 중지';

  @override
  String get settingsTestSpeaker => '스피커 테스트';

  @override
  String get settingsConnectionSection => '연결';

  @override
  String get settingsDefaultNickname => '기본 닉네임';

  @override
  String get settingsIdentityProfile => '신원 프로필';

  @override
  String get settingsIdentityProfileHelper =>
      '모든 서버에서 같은 프로필 이름을 사용하면 동일한 클라이언트 신원이 사용됩니다.';

  @override
  String get settingsAfterDrop => '연결이 끊긴 후';

  @override
  String get settingsReconnectUnlimited => '자동 재연결(횟수 제한 없음)';

  @override
  String settingsReconnectAttempts(int n) {
    return '최대 $n회 재시도';
  }

  @override
  String get settingsReconnectNever => '자동 재연결 안 함';

  @override
  String get settingsNotificationsSection => '알림';

  @override
  String get settingsShortcutsSection => '단축키';

  @override
  String get settingsShortcutsHelp =>
      '오른쪽 입력란을 클릭한 뒤 설정할 조합 키를 누르세요. Esc로 취소하고 Delete로 지웁니다.';

  @override
  String get settingsInterfaceSection => '인터페이스';

  @override
  String get settingsLanguageLabel => '언어';

  @override
  String get settingsLanguageSystem => '시스템 설정 따르기';

  @override
  String get settingsLanguageZh => '简体中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsLanguageZhHant => '繁體中文';

  @override
  String get settingsLanguageJa => '日本語';

  @override
  String get settingsLanguageKo => '한국어';

  @override
  String get settingsThemeLabel => '테마';

  @override
  String get settingsThemeSystem => '시스템 설정 따르기';

  @override
  String get settingsThemeNightcord => 'Nightcord';

  @override
  String get settingsThemeBlack => '검정';

  @override
  String get settingsThemeWhite => '흰색';

  @override
  String get settingsVoiceNotStarted =>
      '음성이 시작되지 않았습니다. 시작하면 사용 중인 기기와 마이크 음량이 여기에 표시됩니다.';

  @override
  String settingsDeviceInUse(String name) {
    return '사용 중: $name';
  }

  @override
  String get settingsNoMicrophone => '마이크 없음';

  @override
  String get settingsMicFellBack => '선택한 마이크를 사용할 수 없어 시스템 기본 기기로 전환했습니다.';

  @override
  String get settingsDeviceLost => '사용 중이던 기기가 분리되었습니다. 음성을 다시 시작하면 복구됩니다.';

  @override
  String get settingsTransmitting => '전송 중';

  @override
  String get settingsBelowThreshold => '임계값 미만, 전송 안 함';

  @override
  String get settingsLevelMeterHint => '마이크 음량(음성 시작 후 표시)';

  @override
  String get settingsNotifyPresence => '멤버 참여 또는 퇴장';

  @override
  String get settingsNotifyPoke => '누군가 나를 찔렀을 때';

  @override
  String get settingsNotifyChannelMessage => '채널 및 서버 메시지';

  @override
  String get settingsNotifyDirectMessage => '개인 메시지';

  @override
  String get settingsNotifyConnection => '연결 끊김과 복구';

  @override
  String get settingsNotifySystem => '창이 앞에 없을 때 시스템 알림 표시';

  @override
  String get settingsSensitivity => '감도';

  @override
  String get settingsSensitivityHint =>
      '값이 높을수록 주변 소음에 덜 반응하고, 더 큰 소리로 말해야 합니다.';

  @override
  String get settingsVolume => '출력 음량';

  @override
  String get settingsVolumeHint =>
      '모든 멤버에게 적용됩니다. 개별 멤버의 음량은 채널 목록에서 따로 조정할 수 있습니다.';

  @override
  String get settingsNoLogDirectory => '이 플랫폼에는 쓸 수 있는 로그 폴더가 없습니다.';

  @override
  String get settingsDeviceMissing => '이전에 선택한 기기를 사용할 수 없어 시스템 기본 기기를 사용합니다.';

  @override
  String get settingsSystemDefault => '시스템 기본';

  @override
  String settingsDeviceDefaultSuffix(String name) {
    return '$name(기본)';
  }

  @override
  String get cancelButton => '취소';

  @override
  String get saveButton => '저장';

  @override
  String get connectAddressLabel => '서버 주소';

  @override
  String get connectNicknameLabel => '닉네임';

  @override
  String get connectServerPasswordLabel => '서버 비밀번호';

  @override
  String get connectServerPasswordHint => '선택 사항';

  @override
  String get connectSaveServer => '서버 저장';

  @override
  String get connectButton => '연결';

  @override
  String get connectSavedServers => '저장된 서버';

  @override
  String get connectMoreTooltip => '더 보기';

  @override
  String get connectRename => '이름 변경';

  @override
  String get connectDelete => '삭제';

  @override
  String get connectSaveServerTitle => '서버 저장';

  @override
  String get connectNameLabel => '이름';

  @override
  String sidebarSessionFallback(int id) {
    return '서버 $id';
  }

  @override
  String get sidebarSheetSaved => '저장됨';

  @override
  String get sidebarBookmarkAdd => '즐겨찾기 추가';

  @override
  String get sidebarBookmarkRemove => '즐겨찾기 해제';

  @override
  String get sidebarEditSaved => '편집';

  @override
  String get bookmarkEditTitle => '저장된 서버 편집';

  @override
  String get sidebarAddServer => '서버 추가';

  @override
  String memberMenu(String name) {
    return '$name 작업';
  }

  @override
  String get memberPoke => '찌르기';

  @override
  String memberPokePrompt(String name) {
    return '$name 찌르기';
  }

  @override
  String get memberPokeMessage => '메시지';

  @override
  String get memberMove => '채널로 이동…';

  @override
  String memberMoveTitle(String name) {
    return '$name 이동';
  }

  @override
  String get memberMoveChannel => '채널';

  @override
  String get memberKickChannel => '채널에서 내보내기';

  @override
  String get memberKickServer => '서버에서 내보내기';

  @override
  String get memberBan => '차단…';

  @override
  String memberBanTitle(String name) {
    return '$name 차단';
  }

  @override
  String get memberBanDuration => '차단 기간';

  @override
  String get memberBanPermanent => '영구';

  @override
  String memberBanMinutes(int count) {
    return '$count분';
  }

  @override
  String memberBanHours(int count) {
    return '$count시간';
  }

  @override
  String memberBanDays(int count) {
    return '$count일';
  }

  @override
  String get memberReason => '사유(선택 사항)';

  @override
  String get memberVolume => '음량 조정…';

  @override
  String memberVolumeTitle(String name) {
    return '$name의 음량';
  }

  @override
  String get memberVolumeHint =>
      '현재 세션에만 적용됩니다. 설정의 \'출력 음량\'은 모든 멤버의 기본 음량을 조정합니다.';

  @override
  String get memberNoPermission => '이 작업에 필요한 서버 권한이 없습니다';

  @override
  String get permissionsTitle => '내 권한';

  @override
  String get permissionsHint => '이 권한은 현재 있는 채널을 기준으로 서버가 알려줍니다.';

  @override
  String get permissionsJoinChannel => '채널 참여';

  @override
  String get permissionsMoveClients => '다른 멤버 이동';

  @override
  String get permissionsSendChannelMessage => '채널 메시지 보내기';

  @override
  String get permissionsSendPrivateMessage => '개인 메시지 보내기';

  @override
  String get permissionsKick => '멤버 내보내기';

  @override
  String get permissionsBan => '멤버 차단';

  @override
  String get permissionsNotReported =>
      '이 서버는 클라이언트에 권한 정보를 알려주지 않아 표시할 수 없습니다.';

  @override
  String get permissionsNone => '모든 사용자가 기본으로 가진 권한 외에는 없습니다.';

  @override
  String get memberAway => '자리 비움';

  @override
  String get memberMuted => '마이크 음소거됨';

  @override
  String get memberDeafened => '스피커 꺼짐';

  @override
  String get memberRecording => '녹음 중';

  @override
  String get connectionStateConnected => '연결됨';

  @override
  String get connectionStateConnecting => '연결 중';

  @override
  String get connectionStateReconnecting => '재연결 중';

  @override
  String get connectionStateDisconnecting => '연결 해제 중';

  @override
  String get connectionStateFailed => '연결 실패';

  @override
  String get connectionStateDisconnected => '연결 안 됨';

  @override
  String get chatHintCompose => '메시지 보내기';

  @override
  String get chatHintReconnecting => '재연결 중…';

  @override
  String get chatHintConnecting => '연결 중…';

  @override
  String get chatHintDisconnected => '연결이 끊어졌습니다';

  @override
  String get chatHintJoinChannel => '채널에 참여해야 메시지를 보낼 수 있습니다';

  @override
  String get chatPrivateLabel => '개인 채팅';

  @override
  String chatPoked(String name) {
    return '$name님이 나를 찔렀습니다';
  }

  @override
  String chatPokedWith(String name, String message) {
    return '$name님이 나를 찔렀습니다: $message';
  }

  @override
  String get chatBackToChannel => '채널로 돌아가기';

  @override
  String get chatNotInChannel => '채널에 참여하지 않음';

  @override
  String chatOnlineCount(int count) {
    return '$count명 온라인';
  }

  @override
  String get chatEmpty => '메시지 없음';

  @override
  String get chatDownload => '다운로드';

  @override
  String get chatFileTransferLater => '파일 전송은 이후 버전에서 지원됩니다';

  @override
  String timestampToday(String clock) {
    return '오늘 $clock';
  }

  @override
  String timestampYesterday(String clock) {
    return '어제 $clock';
  }

  @override
  String timestampThisYear(int month, int day, String clock) {
    return '$month월 $day일 $clock';
  }

  @override
  String timestampOtherYear(int year, int month, int day) {
    return '$year년 $month월 $day일';
  }

  @override
  String get bannerReconnecting => '연결이 끊어졌습니다. 재연결 중…';

  @override
  String bannerRetryCountdown(int seconds, int attempt) {
    return '연결이 끊어졌습니다. $seconds초 후 재시도합니다($attempt번째)';
  }

  @override
  String get bannerDisconnect => '연결 해제';

  @override
  String get voiceUnmuteMic => '음소거 해제';

  @override
  String get voiceDisconnect => '연결 해제';

  @override
  String get voiceDisconnectConfirmTitle => '연결을 해제할까요?';

  @override
  String get voiceDisconnectConfirmBody =>
      '연결을 해제하면 초기 화면으로 돌아가고 현재 채팅 기록도 지워집니다.';

  @override
  String get voiceMuteMic => '마이크 음소거';

  @override
  String get voiceUndeafen => '스피커 켜기';

  @override
  String get voiceDeafen => '스피커 끄기';

  @override
  String get serverSessionEnded => '세션이 종료되었습니다';

  @override
  String get chordFieldIdle => '설정할 조합 키를 누르세요…';

  @override
  String get chordFieldUnset => '설정 안 됨';

  @override
  String shellLogPath(String path) {
    return '로그 위치: $path';
  }

  @override
  String get shellDismissError => '닫기';

  @override
  String get shellOpenLog => '로그 열기';

  @override
  String get errorTimeout => '작업 시간 초과';

  @override
  String errorLagged(int count) {
    return '인터페이스가 이벤트를 너무 느리게 처리해 $count개를 잃었습니다';
  }

  @override
  String get errorCommandFailed => '명령 실행 실패';

  @override
  String get errorJoinDenied => '해당 채널에 참여할 권한이 없습니다';

  @override
  String errorUnparsable(String message) {
    return '이벤트를 해석할 수 없습니다: $message';
  }

  @override
  String errorServerCode(String code) {
    return '서버가 오류 코드 $code를 반환했습니다';
  }

  @override
  String errorPermissionAction(String action) {
    return '권한 부족: \'$action\'을(를) 할 수 없습니다';
  }

  @override
  String errorMissingPermission(String permission) {
    return '권한 #$permission 부족';
  }

  @override
  String errorDeviceMissing(String name) {
    return '기기를 찾을 수 없습니다: $name';
  }

  @override
  String get noticeJoined => '서버에 참여했습니다';

  @override
  String get noticeLeft => '서버에서 나갔습니다';

  @override
  String get noticeSomeone => '누군가';

  @override
  String get noticeServerFallback => '서버';

  @override
  String get noticeConnectionRestored => '연결이 복구되었습니다';

  @override
  String get noticeReconnecting => '연결이 끊어졌습니다. 재연결 중';

  @override
  String get noticeConnectionFailed => '연결 실패';

  @override
  String get crashBannerTitle => '지난 세션이 비정상 종료되었습니다';

  @override
  String crashBannerNotes(int count) {
    return '크래시 기록 $count개 발견';
  }

  @override
  String get crashGenerateReport => '보고서 생성';

  @override
  String get crashOpenFolder => '폴더 열기';

  @override
  String get crashDismiss => '무시';

  @override
  String crashReportWritten(String path) {
    return '보고서 생성됨: $path';
  }

  @override
  String get crashReportFailed => '보고서 생성 실패, 자세한 내용은 로그를 확인하세요';

  @override
  String get errorCoreGone => '코어가 충돌했습니다. 앱을 다시 시작하세요';

  @override
  String get modePushToTalk => '누르고 말하기';

  @override
  String get modeVoiceActivation => '음성 감지';

  @override
  String get modeContinuous => '항상 전송';

  @override
  String get modeMuted => '음소거';

  @override
  String get shortcutMute => '음소거';

  @override
  String get shortcutDeafen => '스피커 끄기';

  @override
  String get shortcutPushToTalk => '누르고 말하기';
}
