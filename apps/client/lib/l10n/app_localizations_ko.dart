// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get backButton => '뒤로';

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
  String get settingsSensitivity => '마이크 감도';

  @override
  String get settingsSensitivityHint =>
      '값이 높을수록 주변 소음에 덜 반응하고, 더 큰 소리로 말해야 합니다.';

  @override
  String get settingsMicGain => '마이크 증폭';

  @override
  String get settingsMicGainHint => '상대방에게 들리는 음량입니다. 맨 아래까지 내리면 무음이 됩니다.';

  @override
  String get settingsMicGainSilent => '무음';

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
  String get voiceAway => '자리 비움 설정';

  @override
  String get voiceBackOnline => '돌아오기';

  @override
  String get awayMessageTitle => '자리 비움 메시지';

  @override
  String get awayMessageLabel => '남길 말';

  @override
  String get awayMessageNote =>
      '서버의 모든 사용자에게 표시되며, 다음에 자리 비움 버튼을 누를 때도 이 내용을 사용합니다.';

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

  @override
  String get gatewayTitle => '게이트웨이 연결';

  @override
  String get gatewayDescription => '게이트웨이 주소를 입력하세요. 토큰은 인증이 설정된 경우에만 필요합니다。';

  @override
  String get gatewayUrlLabel => '게이트웨이 주소';

  @override
  String get gatewayTokenLabel => '액세스 토큰';

  @override
  String get gatewayConnect => '게이트웨이 연결';

  @override
  String get gatewayInvalidUrl =>
      'ws:// 또는 wss:// 주소를 입력하세요. HTTPS에는 wss://가 필요합니다.';

  @override
  String get gatewayTokenRequired => '액세스 토큰을 입력하세요.';

  @override
  String get gatewayConnectionFailed => '주소, 토큰 및 허용된 출처를 확인하세요.';

  @override
  String get webEnableAudio => '음성 활성화';

  @override
  String get webAudioHint => '마이크 접근을 허용하고 음성을 활성화하세요.';

  @override
  String get navigationChannels => '채널';

  @override
  String get voiceHoldToTalk => '누르고 말하기';

  @override
  String get settingsAboutSection => '정보';

  @override
  String aboutVersion(String version) {
    return '버전 $version';
  }

  @override
  String get aboutDescription =>
      '본 프로젝트는 비공식 서드파티 TeamSpeak 3 / TeamSpeak 6 클라이언트이며, TeamSpeak 공식과 어떠한 소속 관계도 없습니다.\n\nNightcord는 게임 《프로젝트 세카이 컬러풀 스테이지! feat.하츠네 미쿠》에 등장하는 가상의 음성 채팅 소프트웨어입니다. 본 프로젝트는 게임 《프로젝트 세카이 컬러풀 스테이지! feat.하츠네 미쿠》 및 관련 미술, 음향 등의 리소스에 대한 저작권이나 기타 지식재산권을 주장하지 않으며, 관련 권리는 각 권리자에게 귀속됩니다. 본 프로젝트는 SEGA, Colorful Palette, Nuverse와 어떠한 소속, 제휴 또는 사용 허가 관계도 없으며, 해당 기업들의 입장을 대변하지 않습니다.';

  @override
  String get aboutProject => '프로젝트';

  @override
  String get aboutLicense => '프로젝트 라이선스';

  @override
  String get aboutOpenSource => '오픈 소스 고지';

  @override
  String get aboutOpenSourceDescription =>
      'Flutter, Dart, Riverpod, tsclientlib, Tokio, cpal, Opus 등을 사용합니다. Flutter 의존성, 각 플랫폼의 Rust Core 및 게이트웨이 의존성, Noto 글꼴 고지를 포함합니다. 각 구성 요소는 원래 라이선스와 저작권을 유지합니다.';

  @override
  String get aboutViewLicenses => '구성 요소 라이선스 보기';

  @override
  String get screenStart => '화면 공유';

  @override
  String get screenStop => '공유 중지';

  @override
  String get screenLeave => '시청 중지';

  @override
  String get screenWatch => '시청';

  @override
  String get screenConnecting => '연결 중…';

  @override
  String get screenViewers => '시청자 수';

  @override
  String get screenFullscreen => '전체 화면';

  @override
  String get fullscreenExit => '전체 화면 종료';

  @override
  String get screenHidePreview => '미리보기 숨기기';

  @override
  String get memberStreaming => '화면 공유 중';

  @override
  String get screenEnded => '화면 공유가 종료되었습니다';

  @override
  String get screenCaptureFailed => '화면을 캡처할 수 없습니다. 화면 녹화 권한을 확인하고 다시 시도하세요.';

  @override
  String get screenRefused => '공유 요청이 거절되었습니다.';

  @override
  String get screenTimeout => '화면 공유 연결 시간이 초과되었습니다. 다시 시도하세요.';

  @override
  String get screenConnectionFailed => '화면 공유 연결에 실패했습니다. 다시 시도하세요.';

  @override
  String get screenTitle => '화면 공유';

  @override
  String get screenSetupSources => '소스 선택';

  @override
  String get screenSetupApps => '애플리케이션';

  @override
  String get screenSetupScreens => '화면';

  @override
  String get screenSetupCameras => '카메라';

  @override
  String get screenSetupNoSources => '공유할 항목을 찾지 못했습니다';

  @override
  String get screenSetupNext => '다음';

  @override
  String get screenSetupBack => '뒤로';

  @override
  String get screenSetupGoLive => '방송 시작';

  @override
  String get screenSetupBasic => '기본 설정';

  @override
  String get screenSetupAdvanced => '고급 설정';

  @override
  String get screenSetupPreset => '프리셋';

  @override
  String get screenSetupSource => '원본';

  @override
  String get screenSetupPresentation => '프레젠테이션';

  @override
  String get screenSetupCaptureAudio => '오디오 캡처';

  @override
  String get screenSetupPrivacy => '공개 범위';

  @override
  String get screenSetupPublic => '공개';

  @override
  String get screenSetupContacts => '연락처';

  @override
  String get screenSetupPrivate => '비공개';

  @override
  String get screenSetupResolution => '해상도';

  @override
  String get screenSetupFps => 'FPS';

  @override
  String get screenSetupVideoBitrate => '비트레이트';

  @override
  String get screenSetupAudioBitrate => '오디오 비트레이트';

  @override
  String get screenSetupViewerLimit => '시청자 제한';

  @override
  String get screenSetupUnlimited => '무제한';

  @override
  String get screenSetupMode => '연결 모드';

  @override
  String get screenSetupSfuUnavailable =>
      '서버가 미디어를 중계해야 하는데 이 클라이언트는 아직 지원하지 않습니다';

  @override
  String get screenSetupHelpPreset =>
      '해상도, 프레임 레이트, 비트레이트를 한 번에 정합니다. 이후 하나라도 바꾸면 직접 만든 조합이 됩니다.';

  @override
  String get screenSetupHelpCaptureAudio => '공유하는 창의 소리도 화면과 함께 보냅니다.';

  @override
  String get screenSetupHelpPrivacy =>
      '“연락처”는 “비공개”와 같습니다. 이 클라이언트에는 대조할 연락처 목록이 없습니다.';

  @override
  String get screenSetupHelpResolution =>
      '인코딩 전에 축소할 크기입니다. 캡처 자체는 항상 원래 크기입니다.';

  @override
  String get screenSetupHelpFps => '초당 보내는 프레임 수입니다. 낮을수록 대역폭을 덜 쓰고 부드럽지 않습니다.';

  @override
  String get screenSetupHelpVideoBitrate =>
      '인코더가 화면에 쓸 수 있는 최대치입니다. 시청자가 보는 화질이 여기서 나옵니다.';

  @override
  String get screenSetupHelpAudioBitrate =>
      '인코더가 소리에 쓸 수 있는 최대치입니다. 오디오 캡처가 켜져 있을 때만 쓰입니다.';

  @override
  String get screenSetupHelpViewerLimit =>
      '동시에 시청할 수 있는 사람 수입니다. “무제한”은 서버에 맡깁니다.';

  @override
  String get screenSetupHelpMode => 'P2P는 시청자마다 직접 보냅니다. 서버를 거치는 중계는 아직 없습니다.';

  @override
  String get screenSetupKbps => 'Kbps';

  @override
  String get screenSetupPreview => '미리보기';

  @override
  String get screenSetupPreviewNote =>
      '미리 보기는 정지 이미지입니다. 미리 볼 수 없는 창도 공유할 수 있습니다.';

  @override
  String get screenPopOut => '창으로 분리';

  @override
  String get screenReturnInline => '작은 창으로 돌아가기';

  @override
  String get screenRequestTitle => '시청 요청';

  @override
  String screenRequestMessage(String name) {
    return '$name 님이 화면 공유를 시청하려고 합니다';
  }

  @override
  String get screenRequestSomeone => '누군가';

  @override
  String get screenRequestAllow => '허용';

  @override
  String get screenRequestDeny => '거부';

  @override
  String get settingsShortcutsReset => '기본값으로 복원';

  @override
  String get avatarUpload => '아바타 업로드';

  @override
  String get avatarRemove => '아바타 삭제';

  @override
  String get avatarTitle => '내 아바타';

  @override
  String get avatarEdit => '아바타 편집';

  @override
  String get avatarEditHint => '이미지를 드래그하여 위치를 조정하고 확대하여 자르세요.';

  @override
  String get avatarZoom => '확대';

  @override
  String get avatarRotate => '회전';

  @override
  String get avatarReset => '초기화';

  @override
  String get avatarInvalidImage =>
      '이미지를 읽을 수 없습니다. 10 MB 이하의 PNG, JPEG 또는 WebP 이미지를 선택하세요.';

  @override
  String get avatarOriginalMissing =>
      '원본 이미지가 저장되어 있지 않습니다. 다시 편집하려면 원본 이미지를 선택하세요.';

  @override
  String get profileTitle => '내 프로필';

  @override
  String get soundsEnabled => '알림 소리 재생';

  @override
  String get soundsHint =>
      '아래 경로에 소리 팩 폴더를 만들고 WAV, MP3 또는 FLAC 파일을 추가하세요(최대 30초, 20 MB).';

  @override
  String get soundsRefresh => '소리 팩 새로고침';

  @override
  String get soundsPack => '알림 소리 팩';

  @override
  String get soundsNone => '재생 안 함';

  @override
  String get soundsPreview => '미리 듣기';

  @override
  String get soundsEmpty => '오디오 파일이 없습니다. 기본 소리는 제공된 후 추가됩니다.';

  @override
  String get soundsMissingPack => '선택한 소리 팩이 없습니다. 다른 팩을 선택하세요.';

  @override
  String get soundsMissingFile => '파일 없음';

  @override
  String get soundsReadError =>
      '소리 팩을 읽을 수 없습니다. 폴더 권한과 config.json을 확인한 후 새로고침하세요.';

  @override
  String get soundsWriteError => '설정을 저장할 수 없습니다. 폴더 쓰기 권한을 확인하세요.';

  @override
  String get soundsPlayError => '재생할 수 없습니다. 오디오 파일과 출력 장치를 확인하세요.';

  @override
  String get soundsUnavailable =>
      '사용자 지정 알림 소리 팩에는 로컬 폴더가 필요하며 현재 네이티브 클라이언트에서 사용할 수 있습니다.';

  @override
  String get soundVoiceJoined => '음성 참여';

  @override
  String get soundVoiceLeft => '음성 나가기';

  @override
  String get soundMicrophoneOff => '마이크 끄기';

  @override
  String get soundMicrophoneOn => '마이크 켜기';

  @override
  String get soundSpeakersOff => '스피커 끄기';

  @override
  String get soundSpeakersOn => '스피커 켜기';

  @override
  String get soundAwayOn => 'AFK 켜기';

  @override
  String get soundAwayOff => 'AFK 끄기';

  @override
  String get soundMessage => '새 메시지';

  @override
  String get soundsOpenFolder => '소리 폴더 열기';

  @override
  String get soundsOpenError => '소리 폴더를 열 수 없습니다. 폴더에 접근할 수 있는지 확인하세요.';

  @override
  String get settingsVad => '음성 활동 감지 (VAD)';

  @override
  String get settingsVadSmart => '스마트 음성 감지 (기본값)';

  @override
  String get settingsVadSmartHint => '음량 기준을 직접 조절하지 않아도 사람의 목소리를 자동으로 감지합니다.';

  @override
  String get settingsVadWaiting => '음성 감지 대기 중';

  @override
  String get settingsMicBoostHint =>
      '송신 음량은 기본으로 6 dB 높아집니다. 마이크 게인은 이 음량을 기준으로 조절합니다.';
}
