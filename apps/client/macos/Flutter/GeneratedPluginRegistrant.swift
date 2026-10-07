//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import desktop_multi_window
import flutter_webrtc
import hotkey_manager_macos
import local_notifier
import screen_retriever_macos
import window_manager

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  FlutterMultiWindowPlugin.register(with: registry.registrar(forPlugin: "FlutterMultiWindowPlugin"))
  FlutterWebRTCPlugin.register(with: registry.registrar(forPlugin: "FlutterWebRTCPlugin"))
  HotkeyManagerMacosPlugin.register(with: registry.registrar(forPlugin: "HotkeyManagerMacosPlugin"))
  LocalNotifierPlugin.register(with: registry.registrar(forPlugin: "LocalNotifierPlugin"))
  ScreenRetrieverMacosPlugin.register(with: registry.registrar(forPlugin: "ScreenRetrieverMacosPlugin"))
  WindowManagerPlugin.register(with: registry.registrar(forPlugin: "WindowManagerPlugin"))
}
