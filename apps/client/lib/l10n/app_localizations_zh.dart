// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get backButton => '返回';

  @override
  String get logLabel => '日志';

  @override
  String get openLogFolder => '打开日志文件夹';

  @override
  String get startupFailureTitle => '核心启动失败';

  @override
  String get stackTraceLabel => '堆栈信息';

  @override
  String get startupFailureLogHint => '本次启动的日志（如果有）保存在此文件中：';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsLoading => '正在加载设置…';

  @override
  String get settingsAudioSection => '音频';

  @override
  String get settingsMicrophoneLabel => '麦克风';

  @override
  String get settingsSpeakerLabel => '扬声器';

  @override
  String get settingsTransmissionMode => '传输模式';

  @override
  String get settingsDeviceChangeNote => '更换设备后将立即重新初始化音频。';

  @override
  String get settingsConnectFirst => '连接服务器后即可测试麦克风。';

  @override
  String get settingsTestMicrophone => '测试麦克风';

  @override
  String get settingsStopTest => '停止测试';

  @override
  String get settingsTestSpeaker => '测试扬声器';

  @override
  String get settingsConnectionSection => '连接';

  @override
  String get settingsDefaultNickname => '默认昵称';

  @override
  String get settingsIdentityProfile => '身份配置';

  @override
  String get settingsIdentityProfileHelper => '在所有服务器上使用相同的配置名称时，将使用同一个客户端身份。';

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
      '点击右侧输入框，然后按下要设置的组合键。按 Esc 取消，按 Delete 清除。';

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
  String get settingsLanguageZhHant => '繁體中文';

  @override
  String get settingsLanguageJa => '日本語';

  @override
  String get settingsLanguageKo => '한국어';

  @override
  String get settingsThemeLabel => '主题';

  @override
  String get settingsThemeSystem => '跟随系统';

  @override
  String get settingsThemeNightcord => 'Nightcord';

  @override
  String get settingsThemeBlack => '纯黑';

  @override
  String get settingsThemeWhite => '纯白';

  @override
  String get settingsVoiceNotStarted => '语音尚未开始。开始语音后，这里会显示当前使用的设备和麦克风音量。';

  @override
  String settingsDeviceInUse(String name) {
    return '当前设备：$name';
  }

  @override
  String get settingsNoMicrophone => '未检测到麦克风';

  @override
  String get settingsMicFellBack => '所选麦克风不可用，已切换到系统默认设备。';

  @override
  String get settingsDeviceLost => '正在使用的设备已断开。重新开始语音即可恢复。';

  @override
  String get settingsTransmitting => '正在传输';

  @override
  String get settingsBelowThreshold => '低于阈值，未传输';

  @override
  String get settingsLevelMeterHint => '麦克风音量（开始语音后显示）';

  @override
  String get settingsNotifyPresence => '成员加入或离开';

  @override
  String get settingsNotifyPoke => '有人向你发送戳一戳';

  @override
  String get settingsNotifyChannelMessage => '频道和服务器消息';

  @override
  String get settingsNotifyDirectMessage => '私聊消息';

  @override
  String get settingsNotifyConnection => '连接断开与恢复';

  @override
  String get settingsNotifySystem => '窗口不在前台时显示系统通知';

  @override
  String get settingsSensitivity => '灵敏度';

  @override
  String get settingsSensitivityHint => '灵敏度越高，越不容易被环境噪音触发，但需要更大声说话才能触发。';

  @override
  String get settingsMicGain => '麦克风增益';

  @override
  String get settingsMicGainHint => '其他人听到你的音量。拖到最底端为静音。';

  @override
  String get settingsMicGainSilent => '静音';

  @override
  String get settingsVolume => '输出音量';

  @override
  String get settingsVolumeHint => '调整所有成员的默认音量。你也可以在频道列表中单独调整某个成员的音量。';

  @override
  String get settingsNoLogDirectory => '此平台没有可写的日志目录。';

  @override
  String get settingsDeviceMissing => '上次选择的设备已不可用，将使用系统默认设备。';

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
  String get connectNicknameLabel => '昵称';

  @override
  String get connectServerPasswordLabel => '服务器密码';

  @override
  String get connectServerPasswordHint => '可选';

  @override
  String get connectSaveServer => '保存服务器';

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
  String sidebarSessionFallback(int id) {
    return '服务器 $id';
  }

  @override
  String get sidebarSheetSaved => '已保存';

  @override
  String get sidebarBookmarkAdd => '收藏服务器';

  @override
  String get sidebarBookmarkRemove => '取消收藏';

  @override
  String get sidebarEditSaved => '编辑';

  @override
  String get bookmarkEditTitle => '编辑收藏的服务器';

  @override
  String get sidebarAddServer => '添加服务器';

  @override
  String memberMenu(String name) {
    return '$name 的操作';
  }

  @override
  String get memberPoke => '戳一戳';

  @override
  String memberPokePrompt(String name) {
    return '戳一戳 $name';
  }

  @override
  String get memberPokeMessage => '留言';

  @override
  String get memberMove => '移动到频道…';

  @override
  String memberMoveTitle(String name) {
    return '移动 $name';
  }

  @override
  String get memberMoveChannel => '频道';

  @override
  String get memberKickChannel => '移出频道';

  @override
  String get memberKickServer => '移出服务器';

  @override
  String get memberBan => '封禁…';

  @override
  String memberBanTitle(String name) {
    return '封禁 $name';
  }

  @override
  String get memberBanDuration => '封禁时长';

  @override
  String get memberBanPermanent => '永久';

  @override
  String memberBanMinutes(int count) {
    return '$count 分钟';
  }

  @override
  String memberBanHours(int count) {
    return '$count 小时';
  }

  @override
  String memberBanDays(int count) {
    return '$count 天';
  }

  @override
  String get memberReason => '原因（可选）';

  @override
  String get memberVolume => '调整音量…';

  @override
  String memberVolumeTitle(String name) {
    return '$name 的音量';
  }

  @override
  String get memberVolumeHint => '仅对当前会话有效。设置中的「输出音量」会调整所有成员的默认音量。';

  @override
  String get memberNoPermission => '你没有执行此操作所需的服务器权限';

  @override
  String get permissionsTitle => '我的权限';

  @override
  String get permissionsHint => '这些权限由服务器根据你当前所在的频道提供。';

  @override
  String get permissionsJoinChannel => '加入频道';

  @override
  String get permissionsMoveClients => '移动其他成员';

  @override
  String get permissionsSendChannelMessage => '发送频道消息';

  @override
  String get permissionsSendPrivateMessage => '发送私聊消息';

  @override
  String get permissionsKick => '移出成员';

  @override
  String get permissionsBan => '封禁成员';

  @override
  String get permissionsNotReported => '此服务器不会向客户端提供权限信息，因此无法显示。';

  @override
  String get permissionsNone => '除所有用户默认拥有的权限外，没有其他权限。';

  @override
  String get memberAway => '离开';

  @override
  String get memberMuted => '麦克风已静音';

  @override
  String get memberDeafened => '扬声器已关闭';

  @override
  String get memberRecording => '正在录音';

  @override
  String get connectionStateConnected => '已连接';

  @override
  String get connectionStateConnecting => '正在连接';

  @override
  String get connectionStateReconnecting => '正在重连';

  @override
  String get connectionStateDisconnecting => '正在断开';

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
  String get chatHintJoinChannel => '加入频道后才能发送消息';

  @override
  String get chatPrivateLabel => '私聊';

  @override
  String chatPoked(String name) {
    return '$name 戳了戳你';
  }

  @override
  String chatPokedWith(String name, String message) {
    return '$name 戳了戳你：$message';
  }

  @override
  String get chatBackToChannel => '返回频道';

  @override
  String get chatNotInChannel => '未加入频道';

  @override
  String chatOnlineCount(int count) {
    return '$count 人在线';
  }

  @override
  String get chatEmpty => '暂无消息';

  @override
  String get chatDownload => '下载';

  @override
  String get chatFileTransferLater => '文件传输功能将在后续版本中支持';

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
    return '$year年$month月$day日';
  }

  @override
  String get bannerReconnecting => '连接已断开，正在重连…';

  @override
  String bannerRetryCountdown(int seconds, int attempt) {
    return '连接已断开，将在 $seconds 秒后重试（第 $attempt 次）';
  }

  @override
  String get bannerDisconnect => '断开连接';

  @override
  String get voiceUnmuteMic => '取消静音';

  @override
  String get voiceDisconnect => '断开连接';

  @override
  String get voiceDisconnectConfirmTitle => '断开连接？';

  @override
  String get voiceDisconnectConfirmBody => '断开后将返回初始页面，当前聊天记录也会清除。';

  @override
  String get voiceMuteMic => '静音麦克风';

  @override
  String get voiceUndeafen => '打开扬声器';

  @override
  String get voiceDeafen => '关闭扬声器';

  @override
  String get voiceAway => '设为离开';

  @override
  String get voiceBackOnline => '回到在线';

  @override
  String get awayMessageTitle => '离开消息';

  @override
  String get awayMessageLabel => '要说的话';

  @override
  String get awayMessageNote => '服务器上的其他人都会看到这条消息；下次点离开按钮还会用它。';

  @override
  String get serverSessionEnded => '会话已结束';

  @override
  String get chordFieldIdle => '按下要设置的组合键…';

  @override
  String get chordFieldUnset => '未设置';

  @override
  String shellLogPath(String path) {
    return '日志位置：$path';
  }

  @override
  String get shellDismissError => '关闭';

  @override
  String get shellOpenLog => '打开日志';

  @override
  String get errorTimeout => '操作超时';

  @override
  String errorLagged(int count) {
    return '界面处理事件过慢，已丢失 $count 个事件';
  }

  @override
  String get errorCommandFailed => '命令执行失败';

  @override
  String get errorJoinDenied => '没有权限加入该频道';

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
    return '权限不足：无法执行“$action”';
  }

  @override
  String errorMissingPermission(String permission) {
    return '缺少权限 #$permission';
  }

  @override
  String errorDeviceMissing(String name) {
    return '找不到设备：$name';
  }

  @override
  String get noticeJoined => '已加入服务器';

  @override
  String get noticeLeft => '已离开服务器';

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
  String get crashBannerTitle => '上次会话异常结束';

  @override
  String crashBannerNotes(int count) {
    return '发现 $count 份崩溃记录';
  }

  @override
  String get crashGenerateReport => '生成报告';

  @override
  String get crashOpenFolder => '打开文件夹';

  @override
  String get crashDismiss => '忽略';

  @override
  String crashReportWritten(String path) {
    return '报告已生成：$path';
  }

  @override
  String get crashReportFailed => '报告生成失败，详细信息请查看日志';

  @override
  String get errorCoreGone => '核心已崩溃，请重启应用';

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
  String get shortcutDeafen => '关闭扬声器';

  @override
  String get shortcutPushToTalk => '按键说话';

  @override
  String get gatewayTitle => '连接到你的网关';

  @override
  String get gatewayDescription => '输入网关地址即可连接，仅在网关启用鉴权时需要访问密钥。';

  @override
  String get gatewayUrlLabel => '网关地址';

  @override
  String get gatewayTokenLabel => '访问令牌';

  @override
  String get gatewayConnect => '连接网关';

  @override
  String get gatewayInvalidUrl => '请输入 ws:// 或 wss:// 地址；HTTPS 页面须使用 wss://。';

  @override
  String get gatewayTokenRequired => '请输入网关访问令牌。';

  @override
  String get gatewayConnectionFailed => '连接失败，请检查地址、令牌以及网关允许的页面来源。';

  @override
  String get webEnableAudio => '启用语音';

  @override
  String get webAudioHint => '请允许麦克风权限并启用语音，加入对话。';

  @override
  String get navigationChannels => '频道';

  @override
  String get voiceHoldToTalk => '按住说话';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');

  @override
  String get backButton => '返回';

  @override
  String get logLabel => '日誌';

  @override
  String get openLogFolder => '開啟日誌資料夾';

  @override
  String get startupFailureTitle => '核心啟動失敗';

  @override
  String get stackTraceLabel => '堆疊資訊';

  @override
  String get startupFailureLogHint => '本次啟動的日誌（如果有）保存在這個檔案中：';

  @override
  String get settingsTitle => '設定';

  @override
  String get settingsLoading => '正在載入設定…';

  @override
  String get settingsAudioSection => '音訊';

  @override
  String get settingsMicrophoneLabel => '麥克風';

  @override
  String get settingsSpeakerLabel => '喇叭';

  @override
  String get settingsTransmissionMode => '傳輸模式';

  @override
  String get settingsDeviceChangeNote => '更換裝置後會立即重新初始化音訊。';

  @override
  String get settingsConnectFirst => '連線伺服器後即可測試麥克風。';

  @override
  String get settingsTestMicrophone => '測試麥克風';

  @override
  String get settingsStopTest => '停止測試';

  @override
  String get settingsTestSpeaker => '測試喇叭';

  @override
  String get settingsConnectionSection => '連線';

  @override
  String get settingsDefaultNickname => '預設暱稱';

  @override
  String get settingsIdentityProfile => '身分設定檔';

  @override
  String get settingsIdentityProfileHelper => '在所有伺服器上使用相同的設定檔名稱時，會使用同一個用戶端身分。';

  @override
  String get settingsAfterDrop => '斷線後';

  @override
  String get settingsReconnectUnlimited => '自動重連（不限次數）';

  @override
  String settingsReconnectAttempts(int n) {
    return '最多重試 $n 次';
  }

  @override
  String get settingsReconnectNever => '不自動重連';

  @override
  String get settingsNotificationsSection => '通知';

  @override
  String get settingsShortcutsSection => '快捷鍵';

  @override
  String get settingsShortcutsHelp =>
      '點選右側輸入框，然後按下要設定的組合鍵。按 Esc 取消，按 Delete 清除。';

  @override
  String get settingsInterfaceSection => '介面';

  @override
  String get settingsLanguageLabel => '語言';

  @override
  String get settingsLanguageSystem => '跟隨系統';

  @override
  String get settingsLanguageZh => '簡體中文';

  @override
  String get settingsLanguageEn => 'English';

  @override
  String get settingsLanguageZhHant => '繁體中文';

  @override
  String get settingsLanguageJa => '日本語';

  @override
  String get settingsLanguageKo => '한국어';

  @override
  String get settingsThemeLabel => '主題';

  @override
  String get settingsThemeSystem => '跟隨系統';

  @override
  String get settingsThemeNightcord => 'Nightcord';

  @override
  String get settingsThemeBlack => '純黑';

  @override
  String get settingsThemeWhite => '純白';

  @override
  String get settingsVoiceNotStarted => '語音尚未開始。開始語音後，這裡會顯示目前使用的裝置和麥克風音量。';

  @override
  String settingsDeviceInUse(String name) {
    return '目前裝置：$name';
  }

  @override
  String get settingsNoMicrophone => '未偵測到麥克風';

  @override
  String get settingsMicFellBack => '所選麥克風無法使用，已切換到系統預設裝置。';

  @override
  String get settingsDeviceLost => '正在使用的裝置已中斷連線。重新開始語音即可恢復。';

  @override
  String get settingsTransmitting => '正在傳輸';

  @override
  String get settingsBelowThreshold => '低於閾值，未傳輸';

  @override
  String get settingsLevelMeterHint => '麥克風音量（開始語音後顯示）';

  @override
  String get settingsNotifyPresence => '成員加入或離開';

  @override
  String get settingsNotifyPoke => '有人戳你一下';

  @override
  String get settingsNotifyChannelMessage => '頻道和伺服器訊息';

  @override
  String get settingsNotifyDirectMessage => '私訊';

  @override
  String get settingsNotifyConnection => '連線中斷與恢復';

  @override
  String get settingsNotifySystem => '視窗不在前景時顯示系統通知';

  @override
  String get settingsSensitivity => '靈敏度';

  @override
  String get settingsSensitivityHint => '靈敏度越高，越不容易被環境噪音觸發，但需要更大聲說話才能觸發。';

  @override
  String get settingsMicGain => '麥克風增益';

  @override
  String get settingsMicGainHint => '其他人聽到你的音量。拖到最底端為靜音。';

  @override
  String get settingsMicGainSilent => '靜音';

  @override
  String get settingsVolume => '輸出音量';

  @override
  String get settingsVolumeHint => '調整所有成員的預設音量。你也可以在頻道清單中個別調整某個成員的音量。';

  @override
  String get settingsNoLogDirectory => '此平台沒有可寫入的日誌目錄。';

  @override
  String get settingsDeviceMissing => '上次選擇的裝置已無法使用，將使用系統預設裝置。';

  @override
  String get settingsSystemDefault => '系統預設';

  @override
  String settingsDeviceDefaultSuffix(String name) {
    return '$name（預設）';
  }

  @override
  String get cancelButton => '取消';

  @override
  String get saveButton => '儲存';

  @override
  String get connectAddressLabel => '伺服器位址';

  @override
  String get connectNicknameLabel => '暱稱';

  @override
  String get connectServerPasswordLabel => '伺服器密碼';

  @override
  String get connectServerPasswordHint => '選填';

  @override
  String get connectSaveServer => '儲存伺服器';

  @override
  String get connectButton => '連線';

  @override
  String get connectSavedServers => '已儲存的伺服器';

  @override
  String get connectMoreTooltip => '更多';

  @override
  String get connectRename => '重新命名';

  @override
  String get connectDelete => '刪除';

  @override
  String get connectSaveServerTitle => '儲存伺服器';

  @override
  String get connectNameLabel => '名稱';

  @override
  String sidebarSessionFallback(int id) {
    return '伺服器 $id';
  }

  @override
  String get sidebarSheetSaved => '已儲存';

  @override
  String get sidebarBookmarkAdd => '收藏伺服器';

  @override
  String get sidebarBookmarkRemove => '取消收藏';

  @override
  String get sidebarEditSaved => '編輯';

  @override
  String get bookmarkEditTitle => '編輯收藏的伺服器';

  @override
  String get sidebarAddServer => '新增伺服器';

  @override
  String memberMenu(String name) {
    return '$name 的操作';
  }

  @override
  String get memberPoke => '戳一下';

  @override
  String memberPokePrompt(String name) {
    return '戳一下 $name';
  }

  @override
  String get memberPokeMessage => '留言';

  @override
  String get memberMove => '移動到頻道…';

  @override
  String memberMoveTitle(String name) {
    return '移動 $name';
  }

  @override
  String get memberMoveChannel => '頻道';

  @override
  String get memberKickChannel => '移出頻道';

  @override
  String get memberKickServer => '移出伺服器';

  @override
  String get memberBan => '封鎖…';

  @override
  String memberBanTitle(String name) {
    return '封鎖 $name';
  }

  @override
  String get memberBanDuration => '封鎖時長';

  @override
  String get memberBanPermanent => '永久';

  @override
  String memberBanMinutes(int count) {
    return '$count 分鐘';
  }

  @override
  String memberBanHours(int count) {
    return '$count 小時';
  }

  @override
  String memberBanDays(int count) {
    return '$count 天';
  }

  @override
  String get memberReason => '原因（選填）';

  @override
  String get memberVolume => '調整音量…';

  @override
  String memberVolumeTitle(String name) {
    return '$name 的音量';
  }

  @override
  String get memberVolumeHint => '僅對目前的工作階段有效。設定中的「輸出音量」會調整所有成員的預設音量。';

  @override
  String get memberNoPermission => '你沒有執行此操作所需的伺服器權限';

  @override
  String get permissionsTitle => '我的權限';

  @override
  String get permissionsHint => '這些權限由伺服器根據你目前所在的頻道提供。';

  @override
  String get permissionsJoinChannel => '加入頻道';

  @override
  String get permissionsMoveClients => '移動其他成員';

  @override
  String get permissionsSendChannelMessage => '傳送頻道訊息';

  @override
  String get permissionsSendPrivateMessage => '傳送私訊';

  @override
  String get permissionsKick => '移出成員';

  @override
  String get permissionsBan => '封鎖成員';

  @override
  String get permissionsNotReported => '此伺服器不會向用戶端提供權限資訊，因此無法顯示。';

  @override
  String get permissionsNone => '除所有使用者預設擁有的權限外，沒有其他權限。';

  @override
  String get memberAway => '暫離';

  @override
  String get memberMuted => '麥克風已靜音';

  @override
  String get memberDeafened => '喇叭已關閉';

  @override
  String get memberRecording => '正在錄音';

  @override
  String get connectionStateConnected => '已連線';

  @override
  String get connectionStateConnecting => '正在連線';

  @override
  String get connectionStateReconnecting => '正在重連';

  @override
  String get connectionStateDisconnecting => '正在中斷連線';

  @override
  String get connectionStateFailed => '連線失敗';

  @override
  String get connectionStateDisconnected => '未連線';

  @override
  String get chatHintCompose => '傳送訊息';

  @override
  String get chatHintReconnecting => '正在重連…';

  @override
  String get chatHintConnecting => '正在連線…';

  @override
  String get chatHintDisconnected => '連線已中斷';

  @override
  String get chatHintJoinChannel => '加入頻道後才能傳送訊息';

  @override
  String get chatPrivateLabel => '私訊';

  @override
  String chatPoked(String name) {
    return '$name 戳了你一下';
  }

  @override
  String chatPokedWith(String name, String message) {
    return '$name 戳了你一下：$message';
  }

  @override
  String get chatBackToChannel => '返回頻道';

  @override
  String get chatNotInChannel => '未加入頻道';

  @override
  String chatOnlineCount(int count) {
    return '$count 人在線';
  }

  @override
  String get chatEmpty => '尚無訊息';

  @override
  String get chatDownload => '下載';

  @override
  String get chatFileTransferLater => '檔案傳輸功能將在後續版本中支援';

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
    return '$year年$month月$day日';
  }

  @override
  String get bannerReconnecting => '連線已中斷，正在重連…';

  @override
  String bannerRetryCountdown(int seconds, int attempt) {
    return '連線已中斷，將在 $seconds 秒後重試（第 $attempt 次）';
  }

  @override
  String get bannerDisconnect => '中斷連線';

  @override
  String get voiceUnmuteMic => '取消靜音';

  @override
  String get voiceDisconnect => '中斷連線';

  @override
  String get voiceDisconnectConfirmTitle => '中斷連線？';

  @override
  String get voiceDisconnectConfirmBody => '中斷後將返回初始頁面，目前的聊天記錄也會清除。';

  @override
  String get voiceMuteMic => '靜音麥克風';

  @override
  String get voiceUndeafen => '開啟喇叭';

  @override
  String get voiceDeafen => '關閉喇叭';

  @override
  String get voiceAway => '設為離開';

  @override
  String get voiceBackOnline => '回到線上';

  @override
  String get awayMessageTitle => '離開訊息';

  @override
  String get awayMessageLabel => '要說的話';

  @override
  String get awayMessageNote => '伺服器上的其他人都會看到這則訊息；下次點離開按鈕還會用它。';

  @override
  String get serverSessionEnded => '工作階段已結束';

  @override
  String get chordFieldIdle => '按下要設定的組合鍵…';

  @override
  String get chordFieldUnset => '未設定';

  @override
  String shellLogPath(String path) {
    return '日誌位置：$path';
  }

  @override
  String get shellDismissError => '關閉';

  @override
  String get shellOpenLog => '開啟日誌';

  @override
  String get errorTimeout => '操作逾時';

  @override
  String errorLagged(int count) {
    return '介面處理事件過慢，已遺失 $count 個事件';
  }

  @override
  String get errorCommandFailed => '命令執行失敗';

  @override
  String get errorJoinDenied => '沒有權限加入該頻道';

  @override
  String errorUnparsable(String message) {
    return '無法解析事件：$message';
  }

  @override
  String errorServerCode(String code) {
    return '伺服器傳回錯誤碼 $code';
  }

  @override
  String errorPermissionAction(String action) {
    return '權限不足：無法執行「$action」';
  }

  @override
  String errorMissingPermission(String permission) {
    return '缺少權限 #$permission';
  }

  @override
  String errorDeviceMissing(String name) {
    return '找不到裝置：$name';
  }

  @override
  String get noticeJoined => '已加入伺服器';

  @override
  String get noticeLeft => '已離開伺服器';

  @override
  String get noticeSomeone => '有人';

  @override
  String get noticeServerFallback => '伺服器';

  @override
  String get noticeConnectionRestored => '連線已恢復';

  @override
  String get noticeReconnecting => '連線已中斷，正在重連';

  @override
  String get noticeConnectionFailed => '連線失敗';

  @override
  String get crashBannerTitle => '上次工作階段異常結束';

  @override
  String crashBannerNotes(int count) {
    return '發現 $count 份崩潰記錄';
  }

  @override
  String get crashGenerateReport => '產生報告';

  @override
  String get crashOpenFolder => '開啟資料夾';

  @override
  String get crashDismiss => '忽略';

  @override
  String crashReportWritten(String path) {
    return '報告已產生：$path';
  }

  @override
  String get crashReportFailed => '報告產生失敗，詳細資訊請查看日誌';

  @override
  String get errorCoreGone => '核心已崩潰，請重新啟動應用程式';

  @override
  String get modePushToTalk => '按鍵發話';

  @override
  String get modeVoiceActivation => '語音感應';

  @override
  String get modeContinuous => '持續傳輸';

  @override
  String get modeMuted => '靜音';

  @override
  String get shortcutMute => '靜音';

  @override
  String get shortcutDeafen => '關閉喇叭';

  @override
  String get shortcutPushToTalk => '按鍵發話';

  @override
  String get gatewayTitle => '連線至你的閘道';

  @override
  String get gatewayDescription => '輸入閘道位址即可連線，僅在閘道啟用驗證時需要存取金鑰。';

  @override
  String get gatewayUrlLabel => '閘道位址';

  @override
  String get gatewayTokenLabel => '存取權杖';

  @override
  String get gatewayConnect => '連線閘道';

  @override
  String get gatewayInvalidUrl => '請輸入 ws:// 或 wss:// 位址；HTTPS 頁面須使用 wss://。';

  @override
  String get gatewayTokenRequired => '請輸入閘道存取權杖。';

  @override
  String get gatewayConnectionFailed => '連線失敗，請檢查位址、權杖及閘道允許的網頁來源。';

  @override
  String get webEnableAudio => '啟用語音';

  @override
  String get webAudioHint => '請允許麥克風權限並啟用語音，加入對話。';

  @override
  String get navigationChannels => '頻道';

  @override
  String get voiceHoldToTalk => '按住說話';
}
