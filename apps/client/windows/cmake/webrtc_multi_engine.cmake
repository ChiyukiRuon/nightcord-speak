# Keep the process-wide WebRTC runtime alive across secondary engine teardown.
# Generate a patched compilation unit in the build tree, leaving Pub untouched.
get_target_property(webrtc_source_dir flutter_webrtc_plugin SOURCE_DIR)
get_target_property(webrtc_sources flutter_webrtc_plugin SOURCES)
set(webrtc_base "${webrtc_source_dir}/../common/cpp/src/flutter_webrtc_base.cc")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${webrtc_base}")
file(READ "${webrtc_base}" webrtc_code)

set(old_shutdown [=[  if (webrtc_initialized_) {
    LibWebRTC::Terminate();
  }]=])
set(new_shutdown [=[  // SSL and field trials are process-global, while this object is per engine.
  // Terminating here invalidates peers owned by the other Flutter engines.
  // Let process exit release the global runtime; per-engine members still die.
]=])
string(FIND "${webrtc_code}" "${old_shutdown}" shutdown_position)
if(shutdown_position EQUAL -1)
  message(FATAL_ERROR "flutter_webrtc shutdown changed; review the multi-engine patch")
endif()
string(REPLACE "${old_shutdown}" "${new_shutdown}" webrtc_code "${webrtc_code}")

set(old_start [=[  if (field_trials.empty()) {
    LibWebRTC::Initialize();
  } else {
    LibWebRTC::InitializeWithFieldTrials(
        libwebrtc::vector<libwebrtc::string>(field_trials));
  }]=])
set(new_start [=[  // Later engines must not reset field trials used by existing peers.
  static std::once_flag process_initialized;
  std::call_once(process_initialized, [&field_trials] {
    if (field_trials.empty()) {
      LibWebRTC::Initialize();
    } else {
      LibWebRTC::InitializeWithFieldTrials(
          libwebrtc::vector<libwebrtc::string>(field_trials));
    }
  });]=])
string(FIND "${webrtc_code}" "${old_start}" start_position)
if(start_position EQUAL -1)
  message(FATAL_ERROR "flutter_webrtc initialization changed; review the multi-engine patch")
endif()
string(REPLACE "${old_start}" "${new_start}" webrtc_code "${webrtc_code}")

set(patched_base "${CMAKE_CURRENT_BINARY_DIR}/webrtc_multi_engine/flutter_webrtc_base.cc")
file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/webrtc_multi_engine")
file(WRITE "${patched_base}" "${webrtc_code}")
set(replaced_sources "")
foreach(source IN LISTS webrtc_sources)
  if(source MATCHES "(^|/)flutter_webrtc_base\\.cc$")
    list(APPEND replaced_sources "${patched_base}")
  else()
    list(APPEND replaced_sources "${source}")
  endif()
endforeach()
set_property(TARGET flutter_webrtc_plugin PROPERTY SOURCES "${replaced_sources}")

# Event channels must retain their own engine's messenger. The cached plugin
# hotfix uses the most recently registered engine globally, dangling after close.
set(webrtc_common "${webrtc_source_dir}/../common/cpp/src/flutter_common.cc")
set(webrtc_plugin "${webrtc_source_dir}/flutter_webrtc_plugin.cc")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
  "${webrtc_common}" "${webrtc_plugin}")
file(READ "${webrtc_common}" common_code)
file(READ "${webrtc_plugin}" plugin_code)
set(old_registry [=[static void* g_host_messenger = nullptr;

void SetEventChannelHostMessenger(void* messenger_ref) {
  g_host_messenger = messenger_ref;
}]=])
set(new_registry [=[static std::map<BinaryMessenger*, FlutterDesktopMessengerRef> engine_messengers;

void SetEventChannelHostMessenger(void*) {}
void SetEventChannelEngineMessenger(BinaryMessenger* messenger, void* ref) {
  engine_messengers[messenger] = static_cast<FlutterDesktopMessengerRef>(ref);
}
void ForgetEventChannelEngineMessenger(BinaryMessenger* messenger) {
  engine_messengers.erase(messenger);
}]=])
set(old_reference [=[     if (g_host_messenger) {
       host_messenger_ = FlutterDesktopMessengerAddRef(
           static_cast<FlutterDesktopMessengerRef>(g_host_messenger));
     }]=])
set(new_reference [=[     const auto owner = engine_messengers.find(messenger);
     if (owner != engine_messengers.end()) {
       host_messenger_ = FlutterDesktopMessengerAddRef(owner->second);
     }]=])
foreach(anchor IN ITEMS old_registry old_reference)
  string(FIND "${common_code}" "${${anchor}}" position)
  if(position EQUAL -1)
    message(FATAL_ERROR "flutter_webrtc messenger changed; review the multi-engine patch")
  endif()
endforeach()
string(REPLACE "#include <memory>" "#include <memory>\n#include <map>" common_code "${common_code}")
string(REPLACE "${old_registry}" "${new_registry}" common_code "${common_code}")
string(REPLACE "${old_reference}" "${new_reference}" common_code "${common_code}")
string(REPLACE "#include <flutter_plugin_registrar.h>"
  "#include <flutter_plugin_registrar.h>\nvoid SetEventChannelEngineMessenger(BinaryMessenger*, void*);\nvoid ForgetEventChannelEngineMessenger(BinaryMessenger*);"
  plugin_code "${plugin_code}")
set(old_register [=[  SetEventChannelHostMessenger(
      FlutterDesktopPluginRegistrarGetMessenger(registrar));]=])
set(new_register [=[  SetEventChannelEngineMessenger(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar)->messenger(),
      FlutterDesktopPluginRegistrarGetMessenger(registrar));]=])
string(FIND "${plugin_code}" "${old_register}" position)
if(position EQUAL -1)
  message(FATAL_ERROR "flutter_webrtc registrar changed; review the multi-engine patch")
endif()
string(REPLACE "${old_register}" "${new_register}" plugin_code "${plugin_code}")
string(FIND "${plugin_code}" "virtual ~FlutterWebRTCPluginImpl() {}" position)
if(position EQUAL -1)
  message(FATAL_ERROR "flutter_webrtc destructor changed; review the multi-engine patch")
endif()
string(REPLACE "virtual ~FlutterWebRTCPluginImpl() {}"
  "virtual ~FlutterWebRTCPluginImpl() { ForgetEventChannelEngineMessenger(messenger_); }"
  plugin_code "${plugin_code}")
set(patched_common "${CMAKE_CURRENT_BINARY_DIR}/webrtc_multi_engine/flutter_common.cc")
set(patched_plugin "${CMAKE_CURRENT_BINARY_DIR}/webrtc_multi_engine/flutter_webrtc_plugin.cc")
file(WRITE "${patched_common}" "${common_code}")
file(WRITE "${patched_plugin}" "${plugin_code}")
get_target_property(webrtc_sources flutter_webrtc_plugin SOURCES)
set(replaced_sources "")
foreach(source IN LISTS webrtc_sources)
  if(source MATCHES "(^|/)flutter_common\\.cc$")
    list(APPEND replaced_sources "${patched_common}")
  elseif(source MATCHES "(^|/)flutter_webrtc_plugin\\.cc$")
    list(APPEND replaced_sources "${patched_plugin}")
  else()
    list(APPEND replaced_sources "${source}")
  endif()
endforeach()
set_property(TARGET flutter_webrtc_plugin PROPERTY SOURCES "${replaced_sources}")
