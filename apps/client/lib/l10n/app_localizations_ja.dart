// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get backButton => '戻る';

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

  @override
  String get gatewayTitle => 'ゲートウェイに接続';

  @override
  String get gatewayDescription => 'ゲートウェイのアドレスを入力してください。トークンは認証が有効な場合のみ必要です。';

  @override
  String get gatewayUrlLabel => 'ゲートウェイアドレス';

  @override
  String get gatewayTokenLabel => 'アクセストークン';

  @override
  String get gatewayConnect => 'ゲートウェイに接続';

  @override
  String get gatewayInvalidUrl =>
      'ws:// または wss:// を入力してください。HTTPS には wss:// が必要です。';

  @override
  String get gatewayTokenRequired => 'トークンを入力してください。';

  @override
  String get gatewayConnectionFailed => '接続できません。アドレス、トークン、許可されたオリジンを確認してください。';

  @override
  String get webEnableAudio => '音声を有効にする';

  @override
  String get webAudioHint => 'マイクへのアクセスを許可して音声を有効にしてください。';

  @override
  String get navigationChannels => 'チャンネル';

  @override
  String get voiceHoldToTalk => '押して話す';

  @override
  String get settingsAboutSection => 'このアプリについて';

  @override
  String aboutVersion(String version) {
    return 'バージョン $version';
  }

  @override
  String get aboutDescription =>
      '本プロジェクトは、非公式のサードパーティ製 TeamSpeak 3 / TeamSpeak 6 クライアントであり、TeamSpeak 公式とは一切の所属関係がありません。\n\nNightcord は、ゲーム『プロジェクトセカイ カラフルステージ！ feat. 初音ミク』に登場する架空のボイスチャットソフトウェアです。本プロジェクトは、ゲーム『プロジェクトセカイ カラフルステージ！ feat. 初音ミク』および関連する美術・音声などの素材に関する著作権その他の知的財産権を主張しません。関連する権利は、それぞれの権利者に帰属します。本プロジェクトは SEGA、Colorful Palette、Nuverse と一切の所属・提携・許諾関係がなく、これらの企業の見解を代表するものではありません。';

  @override
  String get aboutProject => 'プロジェクト';

  @override
  String get aboutLicense => 'プロジェクトのライセンス';

  @override
  String get aboutOpenSource => 'オープンソースについて';

  @override
  String get aboutOpenSourceDescription =>
      'Flutter、Dart、Riverpod、tsclientlib、Tokio、cpal、Opus などを使用しています。Flutter の依存パッケージ、各プラットフォームの Rust Core とゲートウェイの依存パッケージ、Noto フォントの表記を含みます。各コンポーネントのライセンスと著作権はその権利者に帰属します。';

  @override
  String get aboutViewLicenses => 'コンポーネントのライセンス';

  @override
  String get screenStart => '画面を共有';

  @override
  String get screenStop => '共有を停止';

  @override
  String get screenLeave => '視聴を停止';

  @override
  String get screenWatch => '視聴';

  @override
  String get screenConnecting => '接続中…';

  @override
  String get screenViewers => '視聴者数';

  @override
  String get screenFullscreen => '全画面';

  @override
  String get fullscreenExit => '全画面を終了';

  @override
  String get screenHidePreview => 'プレビューを隠す';

  @override
  String get memberStreaming => '画面を共有中';

  @override
  String get screenEnded => '画面共有が終了しました';

  @override
  String get screenCaptureFailed => '画面を取得できません。画面収録の権限を確認して再試行してください。';

  @override
  String get screenRefused => '共有リクエストが拒否されました。';

  @override
  String get screenTimeout => '画面共有の接続がタイムアウトしました。再試行してください。';

  @override
  String get screenConnectionFailed => '画面共有の接続に失敗しました。再試行してください。';

  @override
  String get screenTitle => '画面共有';

  @override
  String get screenSetupSources => 'ソースを選択';

  @override
  String get screenSetupApps => 'アプリ';

  @override
  String get screenSetupScreens => '画面';

  @override
  String get screenSetupCameras => 'カメラ';

  @override
  String get screenSetupNoSources => '共有できるものが見つかりません';

  @override
  String get screenSetupNext => '次へ';

  @override
  String get screenSetupBack => '戻る';

  @override
  String get screenSetupGoLive => '配信を開始';

  @override
  String get screenSetupBasic => '基本設定';

  @override
  String get screenSetupAdvanced => '詳細設定';

  @override
  String get screenSetupPreset => 'プリセット';

  @override
  String get screenSetupSource => 'ソース';

  @override
  String get screenSetupPresentation => 'プレゼン';

  @override
  String get screenSetupCaptureAudio => '音声をキャプチャ';

  @override
  String get screenSetupPrivacy => 'プライバシー';

  @override
  String get screenSetupPublic => '公開';

  @override
  String get screenSetupContacts => '連絡先';

  @override
  String get screenSetupPrivate => '非公開';

  @override
  String get screenSetupResolution => '解像度';

  @override
  String get screenSetupFps => 'FPS';

  @override
  String get screenSetupVideoBitrate => 'ビットレート';

  @override
  String get screenSetupAudioBitrate => '音声ビットレート';

  @override
  String get screenSetupViewerLimit => '視聴者数制限';

  @override
  String get screenSetupUnlimited => '無制限';

  @override
  String get screenSetupMode => '接続モード';

  @override
  String get screenSetupSfuUnavailable => 'サーバー側でメディアを中継する必要があり、このクライアントは未対応です';

  @override
  String get screenSetupHelpPreset =>
      '解像度・フレームレート・ビットレートをまとめて設定します。あとから変更すると独自の組み合わせになります。';

  @override
  String get screenSetupHelpCaptureAudio => '共有するウィンドウの音声も映像と一緒に送ります。';

  @override
  String get screenSetupHelpPrivacy =>
      '「連絡先」は「非公開」と同じ扱いです。照合できる連絡先がこのクライアントにないためです。';

  @override
  String get screenSetupHelpResolution => 'エンコード前に縮小するサイズです。キャプチャ自体は常に元の大きさです。';

  @override
  String get screenSetupHelpFps => '1秒あたりのフレーム数です。低いほど帯域を食いませんが、なめらかさは失われます。';

  @override
  String get screenSetupHelpVideoBitrate =>
      'エンコーダーが映像に使える上限です。視聴者に見えるのはこの分の画質です。';

  @override
  String get screenSetupHelpAudioBitrate =>
      'エンコーダーが音声に使える上限です。音声キャプチャが有効なときだけ使われます。';

  @override
  String get screenSetupHelpViewerLimit => '同時に視聴できる人数です。「無制限」はサーバーに任せます。';

  @override
  String get screenSetupHelpMode => 'P2P は視聴者ごとに直接送ります。サーバー経由の中継は未実装です。';

  @override
  String get screenSetupKbps => 'Kbps';

  @override
  String get screenSetupPreview => 'プレビュー';

  @override
  String get screenSetupPreviewNote => 'プレビューは静止画です。表示できないウィンドウも共有できます。';

  @override
  String get screenPopOut => 'ウィンドウに分離';

  @override
  String get screenReturnInline => '小窓に戻す';

  @override
  String get screenRequestTitle => '視聴リクエスト';

  @override
  String screenRequestMessage(String name) {
    return '$name さんが画面共有を視聴しようとしています';
  }

  @override
  String get screenRequestSomeone => 'だれか';

  @override
  String get screenRequestAllow => '許可';

  @override
  String get screenRequestDeny => '拒否';

  @override
  String get settingsShortcutsReset => '既定に戻す';

  @override
  String get avatarUpload => 'アバターをアップロード';

  @override
  String get avatarRemove => 'アバターを削除';

  @override
  String get avatarTitle => '自分のアバター';

  @override
  String get avatarEdit => 'アバターを編集';

  @override
  String get avatarEditHint => '画像をドラッグして位置を調整し、拡大して切り抜きます。';

  @override
  String get avatarZoom => '拡大';

  @override
  String get avatarRotate => '回転';

  @override
  String get avatarReset => 'リセット';

  @override
  String get avatarInvalidImage =>
      '画像を読み込めません。10 MB以下のPNG、JPEG、WebP画像を選択してください。';

  @override
  String get avatarOriginalMissing => '元の画像が保存されていません。再編集するには元の画像を選択してください。';

  @override
  String get profileTitle => 'プロフィール';

  @override
  String get soundsEnabled => '通知音を再生';

  @override
  String get soundsHint =>
      '下記のディレクトリに通知音パック用のフォルダーを作成し、WAV・MP3・FLAC ファイル（30 秒・20 MB 以下）を追加してください。';

  @override
  String get soundsRefresh => '通知音パックを更新';

  @override
  String get soundsPack => '通知音パック';

  @override
  String get soundsNone => '再生しない';

  @override
  String get soundsPreview => '試聴';

  @override
  String get soundsEmpty => '音声ファイルがありません。既定の通知音は提供後に追加されます。';

  @override
  String get soundsMissingPack => '選択した通知音パックがありません。別のパックを選んでください。';

  @override
  String get soundsMissingFile => 'ファイルなし';

  @override
  String get soundsReadError =>
      '通知音パックを読み込めません。フォルダーの権限と config.json を確認して更新してください。';

  @override
  String get soundsWriteError => '設定を保存できません。フォルダーへの書き込み権限を確認してください。';

  @override
  String get soundsPlayError => '再生できません。音声ファイルと出力デバイスを確認してください。';

  @override
  String get soundsUnavailable =>
      'カスタム通知音パックはローカルフォルダーが必要なため、現在はネイティブクライアントで利用できます。';

  @override
  String get soundVoiceJoined => '音声に参加';

  @override
  String get soundVoiceLeft => '音声から退出';

  @override
  String get soundMicrophoneOff => 'マイクをオフ';

  @override
  String get soundMicrophoneOn => 'マイクをオン';

  @override
  String get soundSpeakersOff => 'スピーカーをオフ';

  @override
  String get soundSpeakersOn => 'スピーカーをオン';

  @override
  String get soundAwayOn => 'AFK をオン';

  @override
  String get soundAwayOff => 'AFK をオフ';

  @override
  String get soundMessage => '新しいメッセージ';

  @override
  String get soundsOpenFolder => '音声フォルダーを開く';

  @override
  String get soundsOpenError => '音声フォルダーを開けません。フォルダーにアクセスできるか確認してください。';
}
