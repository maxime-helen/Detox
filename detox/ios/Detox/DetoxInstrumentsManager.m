//
//  DetoxInstrumentsManager.m
//  Detox
//
//  Created by Leo Natan (Wix) on 2/17/19.
//  Copyright © 2019 Wix. All rights reserved.
//

#import "DetoxInstrumentsManager.h"
#import "DTXLogging.h"
#include <dlfcn.h>

DTX_CREATE_LOG(DetoxInstrumentsManager)

@interface NSObject ()

@property (class, nonatomic, strong, readonly) id defaultProfilingConfiguration;
@property (nonatomic, readwrite) NSTimeInterval samplingInterval;
@property (nonatomic, readwrite) BOOL recordNetwork;
@property (nonatomic, readwrite) BOOL recordThreadInformation;
@property (nonatomic, readwrite) BOOL collectStackTraces;
@property (nonatomic, readwrite) BOOL symbolicateStackTraces;
@property (atomic, assign, readonly, getter=isRecording) BOOL recording;
@property (nonatomic, copy, null_resettable, readwrite) NSURL* recordingFileURL;

- (void)startProfilingWithConfiguration:(id)configuration;
- (void)continueProfilingWithConfiguration:(id)configuration;
- (void)stopProfilingWithCompletionHandler:(void(^ __nullable)(NSError* __nullable error))completionHandler;

@end

typedef NS_ENUM(NSUInteger, __DTXEventStatus) {
	__DTXEventStatusCompleted,
	__DTXEventStatusError,
	__DTXEventStatusCancelled
};

static Class __DTXProfiler;
static Class __DTXMutableProfilingConfiguration;

static void (*__DTXProfilerAddTag)(NSString* tag);
static NSString* (*__DTXProfilerMarkEventIntervalBegin)(NSString* category, NSString* name, NSString* __nullable message);
static void (*__DTXProfilerMarkEventIntervalEnd)(NSString* identifier, __DTXEventStatus eventStatus, NSString* __nullable endMessage);
static void (*__DTXProfilerMarkEvent)(NSString* category, NSString* name, __DTXEventStatus eventStatus, NSString* __nullable startMessage);

@implementation DetoxInstrumentsManager
{
	id _recorderInstance;
}

+ (void)load
{
	__DTXProfiler = NSClassFromString(@"DTXProfiler");
	
	if(__DTXProfiler == NULL)
	{
		//The user has not linked the Profiler framework. Load it manually.
		
		//TODO: Use launch argument (if it exists) and only then fallback to hardcoded path.
		NSBundle* profilerBundle = [NSBundle bundleWithURL:[NSURL fileURLWithPath:@"/Applications/Detox Instruments.app/Contents/SharedSupport/ProfilerFramework/DTXProfiler.framework"]];
		NSError* error = nil;
		[profilerBundle loadAndReturnError:&error];
		
		if(error != nil)
		{
			dtx_log_error(@"Error loading Profiler framework bundle: %@", error);
		}
	}
	
	__DTXProfiler = NSClassFromString(@"DTXProfiler");
	if(__DTXProfiler == NULL)
	{
		dtx_log_error(@"DTXProfiler class not found—this should not have happened!");
		return;
	}
	
	__DTXMutableProfilingConfiguration = NSClassFromString(@"DTXMutableProfilingConfiguration");
	if(__DTXMutableProfilingConfiguration == NULL)
	{
		dtx_log_error(@"DTXMutableProfilingConfiguration class not found—this should not have happened!");
		return;
	}
	
	__DTXProfilerAddTag = dlsym(RTLD_DEFAULT, "DTXProfilerAddTag");
	__DTXProfilerMarkEventIntervalBegin = dlsym(RTLD_DEFAULT, "DTXProfilerMarkEventIntervalBegin");
	__DTXProfilerMarkEventIntervalEnd = dlsym(RTLD_DEFAULT, "DTXProfilerMarkEventIntervalEnd");
	__DTXProfilerMarkEvent = dlsym(RTLD_DEFAULT, "DTXProfilerMarkEvent");
	
	if(__DTXProfilerAddTag == NULL || __DTXProfilerMarkEventIntervalBegin == NULL || __DTXProfilerMarkEventIntervalEnd == NULL || __DTXProfilerMarkEvent == NULL)
	{
		dtx_log_error(@"One or more DTXProfilerAPI functions are NULL—this should not have happened!");
		return;
	}
}

+ (NSString *)_sanitizeFileNameString:(NSString *)fileName
{
	NSCharacterSet* illegalFileNameCharacters = [NSCharacterSet characterSetWithCharactersInString:@":/\\?%*|\"<>"];
	return [[fileName componentsSeparatedByCharactersInSet:illegalFileNameCharacters] componentsJoinedByString:@"_"];
}

+ (NSURL*)defaultURLForTestName:(NSString*)testName
{
	NSURL* documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
	NSURL* rv = [documents URLByAppendingPathComponent:[self _sanitizeFileNameString:testName]];
	
	NSLog(@"🥶 %@", rv.path);
	
	return rv;
}

- (instancetype)init
{
	self = [super init];
	
	if(self)
	{
		_recorderInstance = [__DTXProfiler new];
	}
	
	return self;
}

- (id)_configForDetoxRecordingWithURL:(NSURL*)URL
{
	id config = [__DTXMutableProfilingConfiguration defaultProfilingConfiguration];
	[config setRecordingFileURL:URL];
	
	//TODO: Finalize the actual config for Detox perf recording.
	[config setRecordNetwork:NO];
	[config setRecordThreadInformation:YES];
	[config setCollectStackTraces:YES];
	[config setSymbolicateStackTraces:YES];
	[config setSamplingInterval:0.1];
	
	return config;
}

- (void)startRecordingAtURL:(NSURL*)URL
{
	[_recorderInstance startProfilingWithConfiguration:[self _configForDetoxRecordingWithURL:URL]];
}

- (void)continueRecordingAtURL:(NSURL*)URL
{
	[_recorderInstance continueProfilingWithConfiguration:[self _configForDetoxRecordingWithURL:URL]];
}

- (void)stopRecordingWithCompletionHandler:(void(^)(NSError* error))completionHandler
{
	if(_recorderInstance == nil || [_recorderInstance isRecording] == NO)
	{
		if(completionHandler != nil)
		{
			completionHandler(nil);
		}
		
		return;
	}
	
	[_recorderInstance stopProfilingWithCompletionHandler:completionHandler];
}

@end
