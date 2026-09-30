// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get closeButton => '关闭';

  @override
  String get logLabel => '日志';

  @override
  String get openLogFolder => '打开日志文件夹';

  @override
  String get startupFailureTitle => '核心未能启动';

  @override
  String get stackTraceLabel => '调用栈';

  @override
  String get startupFailureLogHint => '本次启动的记录（若有）在这个文件里：';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsLoading => '正在读取设置…';

  @override
  String get settingsAudioSection => '音频';

  @override
  String get settingsMicrophoneLabel => '麦克风';

  @override
  String get settingsSpeakerLabel => '扬声器';

  @override
  String get settingsTransmissionMode => '传输方式';

  @override
  String get settingsDeviceChangeNote => '设备改动会在下次「开始语音」时生效。';

  @override
  String get settingsConnectFirst => '连接后可开始语音。';

  @override
  String get settingsStartVoice => '开始语音';

  @override
  String get settingsTestSpeaker => '测试扬声器';

  @override
  String get settingsConnectionSection => '连接';

  @override
  String get settingsDefaultNickname => '默认昵称';

  @override
  String get settingsIdentityProfile => '身份档';

  @override
  String get settingsIdentityProfileHelper => '同一个档名在所有服务器上是同一个客户端身份';

  @override
  String get settingsAfterDrop => '断线后';

  @override
  String get settingsReconnectUnlimited => '自动重连（不限次数）';

  @override
  String settingsReconnectAttempts(int n) {
    return '最多重试 $n 次';
  }

  @override
  String get settingsReconnectNever => '不自动重连';

  @override
  String get settingsNotificationsSection => '通知';

  @override
  String get settingsShortcutsSection => '快捷键';

  @override
  String get settingsShortcutsHelp =>
      '点一下右边的框，然后按下你想要的组合。Esc 取消，Delete 清空（清空后不再触发）。';

  @override
  String get settingsInterfaceSection => '界面';

  @override
  String get settingsLanguageLabel => '语言';

  @override
  String get settingsLanguageSystem => '跟随系统';

  @override
  String get settingsLanguageZh => '简体中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsVoiceNotStarted => '尚未开始语音。开始语音后，这里会显示实际在用的设备与麦克风电平。';

  @override
  String settingsDeviceInUse(String name) {
    return '正在使用：$name';
  }

  @override
  String get settingsNoMicrophone => '没有麦克风';

  @override
  String get settingsMicFellBack => '你选的麦克风不在了，正在使用系统默认。';

  @override
  String get settingsDeviceLost => '设备在使用中断开了。重新开始语音可以恢复。';

  @override
  String get settingsTransmitting => '正在传输';

  @override
  String get settingsBelowThreshold => '低于阈值，未传输';

  @override
  String get settingsLevelMeterHint => '麦克风电平（开始语音后显示）';

  @override
  String get settingsNotifyPresence => '有人加入或离开';

  @override
  String get settingsNotifyPoke => '戳一下';

  @override
  String get settingsNotifyChannelMessage => '频道与服务器消息';

  @override
  String get settingsNotifyDirectMessage => '私聊消息';

  @override
  String get settingsNotifyConnection => '连接断开与恢复';

  @override
  String get settingsNotifySystem => '窗口不在前台时用系统通知';

  @override
  String get settingsNotifyNote => '不提醒你正在看的那个会话——消息已经在你眼前了。';

  @override
  String get settingsSensitivity => '灵敏度';

  @override
  String get settingsSensitivityHint => '越高越不容易被环境噪音触发，也越需要说得响一点。';

  @override
  String get settingsNoLogDirectory =>
      '这个平台没有可写的日志目录，记录只写入标准错误输出。\n（Android 与 iOS 需要由宿主应用提供沙箱路径。）';

  @override
  String get settingsDeviceMissing => '上次选的设备不在了，将使用系统默认';

  @override
  String get settingsSystemDefault => '系统默认';

  @override
  String settingsDeviceDefaultSuffix(String name) {
    return '$name（默认）';
  }

  @override
  String get cancelButton => '取消';

  @override
  String get saveButton => '保存';

  @override
  String get connectAddressLabel => '服务器地址';

  @override
  String get connectAddressHint => 'example.com 或 192.168.1.10:9987';

  @override
  String get connectNicknameLabel => '昵称';

  @override
  String get connectServerPasswordLabel => '服务器密码';

  @override
  String get connectServerPasswordHint => '没有就留空';

  @override
  String get connectSaveServer => '保存这个服务器';

  @override
  String get connectButton => '连接';

  @override
  String get connectSavedServers => '已保存的服务器';

  @override
  String get connectMoreTooltip => '更多';

  @override
  String get connectRename => '重命名';

  @override
  String get connectDelete => '删除';

  @override
  String get connectSaveServerTitle => '保存服务器';

  @override
  String get connectNameLabel => '名称';

  @override
  String sidebarOffline(int count) {
    return '离线 — $count';
  }

  @override
  String sidebarSessionFallback(int id) {
    return '服务器 $id';
  }

  @override
  String get sidebarSheetSaved => '已保存';

  @override
  String get sidebarAddServer => '添加服务器';

  @override
  String get memberAway => '离开';

  @override
  String get memberMuted => '已静音';

  @override
  String get memberRecording => '录音中';

  @override
  String get connectionStateConnected => '已连接';

  @override
  String get connectionStateConnecting => '连接中';

  @override
  String get connectionStateReconnecting => '重连中';

  @override
  String get connectionStateDisconnecting => '断开中';

  @override
  String get connectionStateFailed => '连接失败';

  @override
  String get connectionStateDisconnected => '未连接';

  @override
  String get chatHintCompose => '发送消息';

  @override
  String get chatHintReconnecting => '正在重连…';

  @override
  String get chatHintConnecting => '正在连接…';

  @override
  String get chatHintDisconnected => '连接已断开';

  @override
  String get chatHintJoinChannel => '加入频道后才能发言';

  @override
  String get chatPrivateLabel => '私聊';

  @override
  String get chatBackToChannel => '返回频道';

  @override
  String get chatNotInChannel => '未加入频道';

  @override
  String chatOnlineCount(int count) {
    return '$count 在线';
  }

  @override
  String get chatEmpty => '还没有消息';

  @override
  String get chatDownload => '下载';

  @override
  String get chatFileTransferLater => '文件传输将在下个阶段支持';

  @override
  String timestampToday(String clock) {
    return '今天 $clock';
  }

  @override
  String timestampYesterday(String clock) {
    return '昨天 $clock';
  }

  @override
  String timestampThisYear(int month, int day, String clock) {
    return '$month月$day日 $clock';
  }

  @override
  String timestampOtherYear(int year, int month, int day) {
    return '$year/$month/$day';
  }

  @override
  String get bannerReconnecting => '连接已断开，正在重连…';

  @override
  String bannerRetryCountdown(int seconds, int attempt) {
    return '连接已断开，$seconds 秒后重试（第 $attempt 次）';
  }

  @override
  String get bannerDisconnect => '断开';

  @override
  String get voiceUnmuteMic => '取消静音';

  @override
  String get voiceMuteMic => '静音麦克风';

  @override
  String get voiceUndeafen => '取消耳聋';

  @override
  String get voiceDeafen => '耳聋（关闭扬声器）';

  @override
  String get serverSessionEnded => '会话已结束';

  @override
  String get chordFieldIdle => '按下你想要的组合…';

  @override
  String get chordFieldUnset => '未设置';

  @override
  String shellLogPath(String path) {
    return '日志：$path';
  }

  @override
  String get shellOpenLog => '打开日志';

  @override
  String get errorTimeout => '操作超时';

  @override
  String errorLagged(int count) {
    return '界面跟不上事件速度，已丢失 $count 个事件';
  }

  @override
  String get errorCommandFailed => '命令失败';

  @override
  String get errorJoinDenied => '没有加入该频道的权限';

  @override
  String errorUnparsable(String message) {
    return '无法解析事件：$message';
  }

  @override
  String errorServerCode(String code) {
    return '服务器返回错误码 $code';
  }

  @override
  String errorPermissionAction(String action) {
    return '权限不足：无法 $action';
  }

  @override
  String errorMissingPermission(String permission) {
    return '缺少权限 #$permission';
  }

  @override
  String errorDeviceMissing(String name) {
    return '找不到设备 $name';
  }

  @override
  String get noticeJoined => '加入了服务器';

  @override
  String get noticeLeft => '离开了服务器';

  @override
  String get noticeSomeone => '有人';

  @override
  String get noticeServerFallback => '服务器';

  @override
  String get noticeConnectionRestored => '连接已恢复';

  @override
  String get noticeReconnecting => '连接已断开，正在重连';

  @override
  String get noticeConnectionFailed => '连接失败';

  @override
  String get modePushToTalk => '按键说话';

  @override
  String get modeVoiceActivation => '语音激活';

  @override
  String get modeContinuous => '持续传输';

  @override
  String get modeMuted => '静音';

  @override
  String get shortcutMute => '静音';

  @override
  String get shortcutDeafen => '耳聋';

  @override
  String get shortcutPushToTalk => '按键说话';
}
