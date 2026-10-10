# Windows 安装程序中文资源

`ChineseSimplified.isl` 与 `ChineseTraditional.isl` 取自 Inno Setup 官方仓库
`is-6_7_3` 标签下的 `Files/Languages/Unofficial/`，保留上游翻译者署名，
许可见本目录 `LICENSE.txt`。将文件保存到仓库，使本地与 CI 构建都不需要临时下载翻译。
繁体中文在上游版本基础上补齐了 Inno Setup 6.5+ 的消息键，并移除了过时键，避免
解压、重试及文件校验出错时回退为英文；这些调整写在该文件的英文注释中。

英文、日文、韩文使用编译器自带的 `Default.isl`、`Languages/Japanese.isl` 与
`Languages/Korean.isl`。安装程序默认按 Windows 当前用户的显示语言选中对应语言，
也可在启动时的语言选择框中手动更改。不支持的显示语言默认选中英文。
卸载程序沿用安装时选择的语言；覆盖安装重新检测系统显示语言，避免旧英文安装记录
覆盖当前系统语言。
