// Native regression: both pre-offer transceivers used an empty MID as ID,
// so configuring audio reset video codec preferences to the defaults.
#import <Foundation/Foundation.h>
#import <WebRTC/WebRTC.h>
#import "FlutterWebRTCPlugin.h"
#import "FlutterRTCPeerConnection.h"

int main(void) {
  @autoreleasepool {
    RTCPeerConnectionFactory *factory = [[RTCPeerConnectionFactory alloc]
        initWithEncoderFactory:[[RTCDefaultVideoEncoderFactory alloc] init]
        decoderFactory:[[RTCDefaultVideoDecoderFactory alloc] init]];
    RTCConfiguration *config = [RTCConfiguration new];
    config.sdpSemantics = RTCSdpSemanticsUnifiedPlan;
    RTCPeerConnection *pc = [factory peerConnectionWithConfiguration:config
        constraints:[[RTCMediaConstraints alloc] initWithMandatoryConstraints:nil optionalConstraints:nil]
        delegate:nil];
    RTCRtpTransceiver *video = [pc addTransceiverOfType:RTCRtpMediaTypeVideo];
    RTCRtpTransceiver *audio = [pc addTransceiverOfType:RTCRtpMediaTypeAudio];
    FlutterWebRTCPlugin *plugin = [FlutterWebRTCPlugin new];
    plugin.peerConnectionFactory = factory;
    plugin.peerConnections = [@{@"probe": pc} mutableCopy];
    NSString *videoId = [plugin transceiverToMap:video][@"transceiverId"];
    NSString *audioId = [plugin transceiverToMap:audio][@"transceiverId"];
    BOOL distinct = videoId.length > 0 && audioId.length > 0 && ![videoId isEqual:audioId];
    distinct = distinct && [plugin getRtpTransceiverById:pc Id:@""] == nil;
    __block BOOL preferencesOK = YES;
    NSArray *preferences = @[
      @[@{@"mimeType": @"video/VP8", @"clockRate": @90000},
        @{@"mimeType": @"video/rtx", @"clockRate": @90000}],
      @[@{@"mimeType": @"audio/opus", @"clockRate": @48000, @"channels": @2}]
    ];
    NSArray *ids = @[videoId, audioId];
    for (NSUInteger index = 0; index < ids.count; index++) {
      [plugin transceiverSetCodecPreferences:@{@"peerConnectionId": @"probe",
          @"transceiverId": ids[index], @"codecs": preferences[index]}
          result:^(id value) {
            if ([value isKindOfClass:[FlutterError class]]) preferencesOK = NO;
          }];
    }
    __block BOOL completed = NO;
    __block BOOL codecsOK = YES;
    __block BOOL lookupOK = NO;
    [pc offerForConstraints:[[RTCMediaConstraints alloc] initWithMandatoryConstraints:nil optionalConstraints:nil]
        completionHandler:^(RTCSessionDescription *description, NSError *error) {
          NSMutableArray *codecs = [NSMutableArray new];
          for (NSString *line in [description.sdp componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
            if ([line hasPrefix:@"a=rtpmap:"]) {
              NSString *codec = [[line componentsSeparatedByString:@" "] lastObject];
              [codecs addObject:codec];
              if (![codec isEqual:@"VP8/90000"] && ![codec isEqual:@"rtx/90000"] &&
                  ![codec isEqual:@"opus/48000/2"]) codecsOK = NO;
            }
          }
          codecsOK = codecsOK && !error && [codecs containsObject:@"VP8/90000"] &&
              [codecs containsObject:@"opus/48000/2"];
          printf("distinct=%d preferences=%d codecs=%s\n", distinct, preferencesOK,
              [[codecs componentsJoinedByString:@","] UTF8String]);
          [pc setLocalDescription:description completionHandler:^(NSError *localError) {
            // The SDK can return fresh ObjC wrappers for the same native object.
            RTCRtpTransceiver *resolvedVideo = [plugin getRtpTransceiverById:pc Id:videoId];
            RTCRtpTransceiver *resolvedAudio = [plugin getRtpTransceiverById:pc Id:audioId];
            lookupOK = !localError &&
                [resolvedVideo.sender.senderId isEqual:video.sender.senderId] &&
                [resolvedAudio.sender.senderId isEqual:audio.sender.senderId] &&
                [[plugin getRtpTransceiverById:pc Id:resolvedVideo.mid].sender.senderId isEqual:videoId] &&
                [[plugin getRtpTransceiverById:pc Id:resolvedAudio.mid].sender.senderId isEqual:audioId];
            completed = YES;
          }];
        }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!completed && deadline.timeIntervalSinceNow > 0) {
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    BOOL passed = completed && distinct && preferencesOK && codecsOK && lookupOK;
    printf("completed=%d codecs=%d lookup=%d\n", completed, codecsOK, lookupOK);
    printf("%s\n", passed ? "PASS" : "FAIL");
    [pc close];
    return passed ? 0 : 2;
  }
}
