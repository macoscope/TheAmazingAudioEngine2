//
//  AEUtilities.m
//  TheAmazingAudioEngine
//
//  Created by Michael Tyson on 23/03/2016.
//  Copyright © 2016 A Tasty Pixel. All rights reserved.
//
//  This software is provided 'as-is', without any express or implied
//  warranty.  In no event will the authors be held liable for any damages
//  arising from the use of this software.
//
//  Permission is granted to anyone to use this software for any purpose,
//  including commercial applications, and to alter it and redistribute it
//  freely, subject to the following restrictions:
//
//  1. The origin of this software must not be misrepresented; you must not
//     claim that you wrote the original software. If you use this software
//     in a product, an acknowledgment in the product documentation would be
//     appreciated but is not required.
//
//  2. Altered source versions must be plainly marked as such, and must not be
//     misrepresented as being the original software.
//
//  3. This notice may not be removed or altered from any source distribution.
//

#import "AEUtilities.h"
#import "AETime.h"
#include <AudioToolbox/AudioFormat.h>



void SetFileWriterConfigurationError(OSStatus status, NSError **error)
{
    if ( error ) {
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                     code:status
                                 userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedString(@"Couldn't configure the file writer", @"") }];
    }
}

AudioComponentDescription AEAudioComponentDescriptionMake(OSType manufacturer, OSType type, OSType subtype) {
    AudioComponentDescription description;
    memset(&description, 0, sizeof(description));
    description.componentManufacturer = manufacturer;
    description.componentType = type;
    description.componentSubType = subtype;
    return description;
}

BOOL AERateLimit(void) {
    static double lastMessage = 0;
    static int messageCount=0;
    double now = AECurrentTimeInSeconds();
    if ( now-lastMessage > 1 ) {
        messageCount = 0;
        lastMessage = now;
    }
    if ( ++messageCount >= 10 ) {
        if ( messageCount == 10 ) {
            NSLog(@"TAAE: Suppressing some messages");
        }
        return NO;
    }
    return YES;
}

AudioFileTypeID EXAudioFileTypeToAudioFileTypeID(AEAudioFileType fileType) {
    if ( fileType == AEAudioFileTypeM4A ) {
        return kAudioFileM4AType;

    } else if ( fileType == AEAudioFileTypeAIFFFloat32 ) {
        return kAudioFileAIFCType;

    } else {
        if ( fileType == AEAudioFileTypeAIFFInt16 ) {
            return kAudioFileAIFFType;
        } else {
            return kAudioFileWAVEType;
        }
    }
}

bool EXAudioStreamBasicDescription(AEAudioFileType fileType, double sampleRate, int channelCount, AudioStreamBasicDescription * asbd, NSError ** error) {

    if ( !asbd ) {
        if ( error ) {
            *error = [NSError errorWithDomain:@"AmazingAudioEngineError"
                                         code:123
                                     userInfo:@{ NSLocalizedDescriptionKey : @"Passed AudioStreamBasicDescription pointer to doesn't point to valid AudioStreamBasicDescription instance" }];
        }
        return false;
    }

    *asbd = (AudioStreamBasicDescription){
        .mChannelsPerFrame = channelCount,
        .mSampleRate = sampleRate,
    };

    if ( fileType == AEAudioFileTypeM4A ) {
        // AAC encoding in M4A container
        // Get the output audio description for encoding AAC
        asbd->mFormatID = kAudioFormatMPEG4AAC;
        UInt32 size = sizeof(*asbd);
        OSStatus status = AudioFormatGetProperty(kAudioFormatProperty_FormatInfo, 0, NULL, &size, asbd);
        if ( !AECheckOSStatus(status, "AudioFormatGetProperty(kAudioFormatProperty_FormatInfo") ) {
            int fourCC = CFSwapInt32HostToBig(status);
            if ( error ) *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                                      code:status
                                                  userInfo:@{ NSLocalizedDescriptionKey:
                                                                  [NSString stringWithFormat:NSLocalizedString(@"Couldn't prepare the output format (error %d/%4.4s)", @""), status, (char*)&fourCC]}];
            return false;
        }

    } else if ( fileType == AEAudioFileTypeAIFFFloat32 ) {
        // 32-bit floating point
        asbd->mFormatID = kAudioFormatLinearPCM;
        asbd->mFormatFlags = kLinearPCMFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsBigEndian;
        asbd->mBitsPerChannel = sizeof(float) * 8;
        asbd->mBytesPerPacket = asbd->mChannelsPerFrame * sizeof(float);
        asbd->mBytesPerFrame = asbd->mBytesPerPacket;
        asbd->mFramesPerPacket = 1;

    } else {
        // 16-bit signed integer
        asbd->mFormatID = kAudioFormatLinearPCM;
        asbd->mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked |
        (fileType == AEAudioFileTypeAIFFInt16 ? kAudioFormatFlagIsBigEndian : 0);
        asbd->mBitsPerChannel = 16;
        asbd->mBytesPerPacket = asbd->mChannelsPerFrame * 2;
        asbd->mBytesPerFrame = asbd->mBytesPerPacket;
        asbd->mFramesPerPacket = 1;
    }

    return true;
}

ExtAudioFileRef AEExtAudioFileCreateWithCodecPreference(NSURL * url, AEAudioFileType fileType, bool forceSoftwareCodec, double sampleRate, int channelCount, NSError ** error) {

    ExtAudioFileRef audioFile;
    AudioStreamBasicDescription asbd;
    AudioFileTypeID fileTypeID = EXAudioFileTypeToAudioFileTypeID(fileType);

    if ( !EXAudioStreamBasicDescription(fileType, sampleRate, channelCount, &asbd, error) ) {
        return NULL;
    }
    OSStatus status = ExtAudioFileCreateWithURL((__bridge CFURLRef)url, fileTypeID, &asbd, NULL, kAudioFileFlags_EraseFile,
                                                &audioFile);
    if ( !AECheckOSStatus(status, "ExtAudioFileCreateWithURL") ) {
        if ( error )
            *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                         code:status
                                     userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedString(@"Couldn't open the output file", @"") }];
        return NULL;
    }

    asbd = AEAudioDescriptionWithChannelsAndRate(channelCount, sampleRate);

    if ( forceSoftwareCodec ) {
        UInt32 codecManfacturer = kAppleSoftwareAudioCodecManufacturer;
        status = ExtAudioFileSetProperty(audioFile,
                                         kExtAudioFileProperty_CodecManufacturer,
                                         sizeof(UInt32),
                                         &codecManfacturer);

        if ( !AECheckOSStatus(status, "ExtAudioFileSetProperty") ) {
            ExtAudioFileDispose(audioFile);
            SetFileWriterConfigurationError(status, error);
            return NULL;
        }
    }

    status = ExtAudioFileSetProperty(audioFile,
                                     kExtAudioFileProperty_ClientDataFormat,
                                     sizeof(asbd),
                                     &asbd);


    if ( !AECheckOSStatus(status, "ExtAudioFileSetProperty") ) {
        //Error: Hardware codec already in use. Switch to software codec instead.
        //http://lists.apple.com/archives/coreaudio-api/2009/Aug/msg00066.html
        if ( status == 'hwiu' ) {
            ExtAudioFileDispose(audioFile);
            NSLog(@"Warning: Hardware codec already in use. Switching to software codec.");
            return AEExtAudioFileCreateWithCodecPreference(url, fileType, true, sampleRate, channelCount, error);

        } else {
            ExtAudioFileDispose(audioFile);
            SetFileWriterConfigurationError(status, error);
            return NULL;
        }
    }

    return audioFile;
}

ExtAudioFileRef _Nullable AEExtAudioFileCreate(NSURL * _Nonnull url, AEAudioFileType fileType, double sampleRate,
                                               int channelCount, NSError * _Nullable * _Nullable error)
{
    return AEExtAudioFileCreateWithCodecPreference(url, fileType, false, sampleRate, channelCount, error);
}
