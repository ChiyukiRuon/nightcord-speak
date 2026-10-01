// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get closeButton => '閉じる';

  @override
  String get logLabel => 'ログ';

  @override
  String get openLogFolder => 'ログフォルダを開く';

  @override
  String get startupFailureTitle => 'コアの起動に失敗';

  @override
  String get stackTraceLabel => 'スタックトレース';

  @override
  String get startupFailureLogHint => '今回の起動のログ（ある場合）はこのファイル：';

  @override
  String get settingsTitle => '設定';

  @override
  String get settingsLoading => '設定を読み込み中…';

  @override
  String get settingsAudioSection => 'オーディオ';

  @override
  String get settingsMicrophoneLabel => 'マイク';

  @override
  String get settingsSpeakerLabel => 'スピーカー';

  @override
  String get settingsTransmissionMode => '送信モード';

  @override
  String get settingsDeviceChangeNote => 'デバイス変更後はオーディオを即座に再初期化。';

  @override
  String get settingsConnectFirst => 'マイクのテストはサーバー接続後に可能。';

  @override
  String get settingsTestMicrophone => 'マイクをテスト';

  @override
  String get settingsStopTest => 'テストを停止';

  @override
  String get settingsTestSpeaker => 'スピーカーをテスト';

  @override
  String get settingsConnectionSection => '接続';

  @override
  String get settingsDefaultNickname => '既定のニックネーム';

  @override
  String get settingsIdentityProfile => 'アイデンティティプロファイル';

  @override
  String get settingsIdentityProfileHelper =>
      '同じプロファイル名は、すべてのサーバーで同じクライアントアイデンティティになる。';

  @override
  String get settingsAfterDrop => '切断後';

  @override
  String get settingsReconnectUnlimited => '自動再接続（回数無制限）';

  @override
  String settingsReconnectAttempts(int n) {
    return '最大 $n 回まで再試行';
  }

  @override
  String get settingsReconnectNever => '自動再接続しない';

  @override
  String get settingsNotificationsSection => '通知';

  @override
  String get settingsShortcutsSection => 'ショートカット';

  @override
  String get settingsShortcutsHelp =>
      '右側の入力欄をクリックし、設定したい組み合わせキーを押す。Esc でキャンセル、Delete でクリア。';

  @override
  String get settingsInterfaceSection => '外観';

  @override
  String get settingsLanguageLabel => '言語';

  @override
  String get settingsLanguageSystem => 'システムに従う';

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
  String get settingsThemeLabel => 'テーマ';

  @override
  String get settingsThemeSystem => 'システムに従う';

  @override
  String get settingsThemeNightcord => 'Nightcord';

  @override
  String get settingsThemeBlack => 'ブラック';

  @override
  String get settingsThemeWhite => 'ホワイト';

  @override
  String get settingsVoiceNotStarted => '音声は未開始。開始後は、使用中のデバイスとマイクの音量をここに表示。';

  @override
  String settingsDeviceInUse(String name) {
    return '使用中：$name';
  }

  @override
  String get settingsNoMicrophone => 'マイクが見つからない';

  @override
  String get settingsMicFellBack => '選択したマイクは使用不可。システム既定のデバイスに切り替え。';

  @override
  String get settingsDeviceLost => '使用中のデバイスが切断。音声を開始し直すと復旧。';

  @override
  String get settingsTransmitting => '送信中';

  @override
  String get settingsBelowThreshold => 'しきい値未満・送信なし';

  @override
  String get settingsLevelMeterHint => 'マイクの音量（音声の開始後に表示）';

  @override
  String get settingsNotifyPresence => 'メンバーの参加と退出';

  @override
  String get settingsNotifyPoke => '誰かからのポーク';

  @override
  String get settingsNotifyChannelMessage => 'チャンネルとサーバーのメッセージ';

  @override
  String get settingsNotifyDirectMessage => 'プライベートメッセージ';

  @override
  String get settingsNotifyConnection => '接続の切断と復旧';

  @override
  String get settingsNotifySystem => 'ウィンドウが前面にないときにシステム通知を表示';

  @override
  String get settingsSensitivity => '感度';

  @override
  String get settingsSensitivityHint => '感度が高いほど周囲の騒音では反応しにくく、その分大きな声が必要。';

  @override
  String get settingsMicGain => 'マイクの増幅';

  @override
  String get settingsMicGainHint => '相手に届く音量。一番下まで下げると無音になる。';

  @override
  String get settingsMicGainSilent => '無音';

  @override
  String get settingsVolume => '出力音量';

  @override
  String get settingsVolumeHint => '全メンバー共通の既定音量を調整。個々のメンバーはチャンネルツリーから個別に変更可能。';

  @override
  String get settingsNoLogDirectory => 'このプラットフォームに書き込み可能なログディレクトリはない。';

  @override
  String get settingsDeviceMissing => '前回選択したデバイスは使用不可。システム既定のデバイスを使用。';

  @override
  String get settingsSystemDefault => 'システム既定';

  @override
  String settingsDeviceDefaultSuffix(String name) {
    return '$name（既定）';
  }

  @override
  String get cancelButton => 'キャンセル';

  @override
  String get saveButton => '保存';

  @override
  String get connectAddressLabel => 'サーバーアドレス';

  @override
  String get connectNicknameLabel => 'ニックネーム';

  @override
  String get connectServerPasswordLabel => 'サーバーパスワード';

  @override
  String get connectServerPasswordHint => '省略可';

  @override
  String get connectSaveServer => 'サーバーを保存';

  @override
  String get connectButton => '接続';

  @override
  String get connectSavedServers => '保存済みのサーバー';

  @override
  String get connectMoreTooltip => 'その他';

  @override
  String get connectRename => '名前を変更';

  @override
  String get connectDelete => '削除';

  @override
  String get connectSaveServerTitle => 'サーバーを保存';

  @override
  String get connectNameLabel => '名前';

  @override
  String sidebarSessionFallback(int id) {
    return 'サーバー $id';
  }

  @override
  String get sidebarSheetSaved => '保存済み';

  @override
  String get sidebarBookmarkAdd => 'サーバーをブックマークに追加';

  @override
  String get sidebarBookmarkRemove => 'ブックマークを解除';

  @override
  String get sidebarEditSaved => '編集';

  @override
  String get bookmarkEditTitle => '保存済みサーバーを編集';

  @override
  String get sidebarAddServer => 'サーバーを追加';

  @override
  String memberMenu(String name) {
    return '$name の操作';
  }

  @override
  String get memberPoke => 'ポーク';

  @override
  String memberPokePrompt(String name) {
    return '$name をポーク';
  }

  @override
  String get memberPokeMessage => 'メッセージ';

  @override
  String get memberMove => 'チャンネルへ移動…';

  @override
  String memberMoveTitle(String name) {
    return '$name を移動';
  }

  @override
  String get memberMoveChannel => 'チャンネル';

  @override
  String get memberKickChannel => 'チャンネルからキック';

  @override
  String get memberKickServer => 'サーバーからキック';

  @override
  String get memberBan => 'BAN…';

  @override
  String memberBanTitle(String name) {
    return '$name を BAN';
  }

  @override
  String get memberBanDuration => 'BAN の期間';

  @override
  String get memberBanPermanent => '永久';

  @override
  String memberBanMinutes(int count) {
    return '$count 分';
  }

  @override
  String memberBanHours(int count) {
    return '$count 時間';
  }

  @override
  String memberBanDays(int count) {
    return '$count 日';
  }

  @override
  String get memberReason => '理由（任意）';

  @override
  String get memberVolume => '音量を変更…';

  @override
  String memberVolumeTitle(String name) {
    return '$name の音量';
  }

  @override
  String get memberVolumeHint => 'このセッションでのみ有効。設定の「出力音量」は全メンバー共通の既定音量を調整。';

  @override
  String get memberNoPermission => 'この操作に必要なサーバー権限がない';

  @override
  String get permissionsTitle => '自分の権限';

  @override
  String get permissionsHint => '現在いるチャンネルに基づいて、サーバーから提供される権限。';

  @override
  String get permissionsJoinChannel => 'チャンネルへの参加';

  @override
  String get permissionsMoveClients => '他のメンバーの移動';

  @override
  String get permissionsSendChannelMessage => 'チャンネルメッセージの送信';

  @override
  String get permissionsSendPrivateMessage => 'プライベートメッセージの送信';

  @override
  String get permissionsKick => 'メンバーのキック';

  @override
  String get permissionsBan => 'メンバーの BAN';

  @override
  String get permissionsNotReported => 'このサーバーはクライアントに権限情報を提供しないため、表示できない。';

  @override
  String get permissionsNone => 'すべてのユーザーが既定で持つ権限以外はない。';

  @override
  String get memberAway => '離席中';

  @override
  String get memberMuted => 'マイクはミュート中';

  @override
  String get memberDeafened => 'スピーカーはオフ';

  @override
  String get memberRecording => '録音中';

  @override
  String get connectionStateConnected => '接続済み';

  @override
  String get connectionStateConnecting => '接続中';

  @override
  String get connectionStateReconnecting => '再接続中';

  @override
  String get connectionStateDisconnecting => '切断中';

  @override
  String get connectionStateFailed => '接続に失敗';

  @override
  String get connectionStateDisconnected => '未接続';

  @override
  String get chatHintCompose => 'メッセージを送信';

  @override
  String get chatHintReconnecting => '再接続中…';

  @override
  String get chatHintConnecting => '接続中…';

  @override
  String get chatHintDisconnected => '接続が切断';

  @override
  String get chatHintJoinChannel => 'メッセージの送信にはチャンネルへの参加が必要';

  @override
  String get chatPrivateLabel => 'プライベートチャット';

  @override
  String chatPoked(String name) {
    return '$name があなたをポーク';
  }

  @override
  String chatPokedWith(String name, String message) {
    return '$name があなたをポーク：$message';
  }

  @override
  String get chatBackToChannel => 'チャンネルに戻る';

  @override
  String get chatNotInChannel => 'チャンネル未参加';

  @override
  String chatOnlineCount(int count) {
    return '$count 人オンライン';
  }

  @override
  String get chatEmpty => 'メッセージなし';

  @override
  String get chatDownload => 'ダウンロード';

  @override
  String get chatFileTransferLater => 'ファイル転送は今後のバージョンで対応';

  @override
  String timestampToday(String clock) {
    return '今日 $clock';
  }

  @override
  String timestampYesterday(String clock) {
    return '昨日 $clock';
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
  String get bannerReconnecting => '接続が切断。再接続中…';

  @override
  String bannerRetryCountdown(int seconds, int attempt) {
    return '接続が切断。$seconds 秒後に再試行（$attempt 回目）';
  }

  @override
  String get bannerDisconnect => '切断';

  @override
  String get voiceUnmuteMic => 'ミュートを解除';

  @override
  String get voiceDisconnect => 'サーバーから切断';

  @override
  String get voiceDisconnectConfirmTitle => '切断しますか？';

  @override
  String get voiceDisconnectConfirmBody => '切断すると初期画面に戻り、現在のチャット履歴も消去される。';

  @override
  String get voiceMuteMic => 'マイクをミュート';

  @override
  String get voiceUndeafen => 'スピーカーをオン';

  @override
  String get voiceDeafen => 'スピーカーをオフ';

  @override
  String get voiceAway => '離席中にする';

  @override
  String get voiceBackOnline => '戻る';

  @override
  String get awayMessageTitle => '離席メッセージ';

  @override
  String get awayMessageLabel => '伝える内容';

  @override
  String get awayMessageNote => 'サーバー上の全員に表示される。次に離席ボタンを押したときもこの内容を使う。';

  @override
  String get serverSessionEnded => 'セッション終了';

  @override
  String get chordFieldIdle => '設定する組み合わせキーを押す…';

  @override
  String get chordFieldUnset => '未設定';

  @override
  String shellLogPath(String path) {
    return 'ログの場所：$path';
  }

  @override
  String get shellDismissError => '閉じる';

  @override
  String get shellOpenLog => 'ログを開く';

  @override
  String get errorTimeout => '操作がタイムアウト';

  @override
  String errorLagged(int count) {
    return '画面の処理が追いつかず、$count 件のイベントを破棄';
  }

  @override
  String get errorCommandFailed => 'コマンド実行に失敗';

  @override
  String get errorJoinDenied => 'このチャンネルに参加する権限がない';

  @override
  String errorUnparsable(String message) {
    return 'イベントを解析できない：$message';
  }

  @override
  String errorServerCode(String code) {
    return 'サーバーがエラーコード $code を返した';
  }

  @override
  String errorPermissionAction(String action) {
    return '権限不足：「$action」を実行できない';
  }

  @override
  String errorMissingPermission(String permission) {
    return '権限 #$permission が不足';
  }

  @override
  String errorDeviceMissing(String name) {
    return 'デバイスが見つからない：$name';
  }

  @override
  String get noticeJoined => 'サーバーに参加';

  @override
  String get noticeLeft => 'サーバーから退出';

  @override
  String get noticeSomeone => '誰か';

  @override
  String get noticeServerFallback => 'サーバー';

  @override
  String get noticeConnectionRestored => '接続が復旧';

  @override
  String get noticeReconnecting => '接続が切断、再接続中';

  @override
  String get noticeConnectionFailed => '接続に失敗';

  @override
  String get crashBannerTitle => '前回のセッションは異常終了';

  @override
  String crashBannerNotes(int count) {
    return '$count 件のクラッシュ記録';
  }

  @override
  String get crashGenerateReport => 'レポートを生成';

  @override
  String get crashOpenFolder => 'フォルダを開く';

  @override
  String get crashDismiss => '無視';

  @override
  String crashReportWritten(String path) {
    return 'レポートの生成完了：$path';
  }

  @override
  String get crashReportFailed => 'レポートの生成に失敗。詳細はログを参照。';

  @override
  String get errorCoreGone => 'コアがクラッシュ。アプリを再起動。';

  @override
  String get modePushToTalk => 'プッシュトゥトーク';

  @override
  String get modeVoiceActivation => '音声検出';

  @override
  String get modeContinuous => '連続送信';

  @override
  String get modeMuted => 'ミュート';

  @override
  String get shortcutMute => 'ミュート';

  @override
  String get shortcutDeafen => 'スピーカーをオフ';

  @override
  String get shortcutPushToTalk => 'プッシュトゥトーク';
}
