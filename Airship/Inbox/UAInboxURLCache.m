/*
 Copyright 2009-2013 Urban Airship Inc. All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.

 2. Redistributions in binaryform must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided withthe distribution.

 THIS SOFTWARE IS PROVIDED BY THE URBAN AIRSHIP INC ``AS IS'' AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
 EVENT SHALL URBAN AIRSHIP INC OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "UAInboxURLCache.h"

#import "UAGlobal.h"
#import "UAConfig.h"
#import "UAUtils.h"
#import "UAirship.h"

#define METADATA_NAME @"UAInboxURLCache.metadata"
#define CACHE_SIZE_KEY @"cacheSize"
#define SIZES_KEY @"sizes"
#define ACCESS_KEY @"access"

/**
 * Private methods
 */
@interface UAInboxURLCache()

//get the locations for content and content type files
- (NSString *)getStoragePathForHash:(NSString *)hash;
- (NSString *)getStoragePathForURL:(NSURL *)url;
- (NSString *)getStoragePathForContentTypeWithHash:(NSString *)hash;
- (NSString *)getStoragePathForContentTypeWithURL:(NSURL *)url;

//lookup methods
- (NSArray *)mimeTypeAndCharsetForContentType:(NSString *)contentType;

//housekeeping
- (NSString *)getMetadataPath;
- (NSMutableDictionary *)loadMetadata;
- (void)saveMetadata;
- (void)purge;
- (NSUInteger)deleteCacheEntry:(NSString *)hash;

//store content on disk
- (void)storeContent:(NSData *)content withURL:(NSURL *)url contentType:(NSString *)contentType;
- (BOOL)shouldStoreCachedResponse:(NSCachedURLResponse *)response forRequest:(NSURLRequest *)request;

@property(nonatomic, strong) NSMutableDictionary *metadata;
@property(nonatomic, strong) NSOperationQueue *queue;


@end

@implementation UAInboxURLCache

#pragma mark -
#pragma mark NSURLCache methods
- (id)initWithMemoryCapacity:(NSUInteger)memoryCapacity diskCapacity:(NSUInteger)diskCapacity diskPath:(NSString *)path {
    if (self = [super initWithMemoryCapacity:memoryCapacity diskCapacity:diskCapacity diskPath:path]) {
        self.cacheDirectory = path;

        self.resourceTypes = @[@"image/png", @"image/gif", @"image/jpg", @"image/jpeg", @"text/javascript", @"application/javascript", @"text/css"];
        
        self.actualDiskCapacity = diskCapacity;
        
        self.metadata = [self loadMetadata];
        
        self.queue = [[NSOperationQueue alloc] init];
        self.queue.maxConcurrentOperationCount = 1;
        
    }
    return self;
}


- (NSUInteger)diskCapacity {
    return self.actualDiskCapacity * 50;
}

- (void)storeCachedResponse:(NSCachedURLResponse *)cachedResponse forRequest:(NSURLRequest *)request {
    
    if ([self shouldStoreCachedResponse:cachedResponse forRequest:request]) {
        
        UALOG(@"storeCachedResponse for URL: %@", [request.URL absoluteString]);
        UALOG(@"storeCachedResponse: %@", cachedResponse);
        UALOG(@"MIME type: %@ Encoding: %@", cachedResponse.response.MIMEType, cachedResponse.response.textEncodingName);
        
        __unsafe_unretained NSData *content = cachedResponse.data;
        
        __unsafe_unretained NSURL *url = request.URL;
        
        // default to "text/html" if the server doesn't provide a content type
        __unsafe_unretained NSString *contentType = cachedResponse.response.MIMEType?:@"text/html";
        NSString *textEncoding = cachedResponse.response.textEncodingName;
        if (textEncoding) {
            contentType = [NSString stringWithFormat:@"%@; charset=%@", contentType, textEncoding];
        }
        
        NSMethodSignature *signature = [UAInboxURLCache instanceMethodSignatureForSelector:@selector(storeContent:withURL:contentType:)];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.selector = @selector(storeContent:withURL:contentType:);
        invocation.target = self;
        [invocation setArgument:&content atIndex:2];
        [invocation setArgument:&url atIndex:3];
        [invocation setArgument:&contentType atIndex:4];
        
        NSInvocationOperation *io = [[NSInvocationOperation alloc] initWithInvocation:invocation];
        [self.queue addOperation:io];

    }
    
    else {
        UALOG(@"IGNORE CACHE for %@", request);
    }
}


- (NSCachedURLResponse *)cachedResponseForRequest:(NSURLRequest *)request {
    
    NSCachedURLResponse *cachedResponse = nil;
    
    // retrieve resource from cache or populate if needed
    NSString *contentPath = [self getStoragePathForURL:request.URL];
    NSString *contentTypePath = [self getStoragePathForContentTypeWithURL:request.URL];
    
    if([[NSFileManager defaultManager] fileExistsAtPath:contentPath]) {
        // retrieve it
        NSData *content = [NSData dataWithContentsOfFile:contentPath];
        
        NSString *contentType = [NSString stringWithContentsOfFile:contentTypePath 
                                                          encoding:NSUTF8StringEncoding 
                                                             error:NULL];
        
        NSString *textEncoding = nil;
        
        // if the content type expresses a charset (e.g. text/html; charset=utf8;) we need to break it up
        // into separate arguments so UIWebView doesn't get confused
        NSArray *subTypes = [self mimeTypeAndCharsetForContentType:contentType];

        if (subTypes.count > 0) {
            contentType = [subTypes objectAtIndex:0];
        } else {
            // default to "text/html" if the server doesn't provide a content type
            contentType = @"text/html";
        }

        if(subTypes.count > 1) {
            textEncoding = [subTypes objectAtIndex:1];
        }

        // default to utf-8 when there isn't a textEncoding for html content type
        if (!textEncoding && [@"text/html" isEqualToString:contentType]) {
            textEncoding = @"utf-8";
        }
        
        NSURLResponse *response = [[NSURLResponse alloc] initWithURL:request.URL
                                                             MIMEType:contentType
                                                expectedContentLength:[content length]
                                                     textEncodingName:textEncoding];
        

        cachedResponse = [[NSCachedURLResponse alloc] initWithResponse:response
                                                                  data:content];

        UALOG(@"Uncaching request %@", request);
        UALOG(@"MIME Type: %@ Encoding: %@", contentType, textEncoding);
        
        NSString *hash = [UAUtils md5:[request.URL absoluteString]];
        @synchronized(self.metadata) {
            [[self.metadata objectForKey:ACCESS_KEY] setValue:[NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]] forKey:hash];
            NSInvocationOperation *io = [[NSInvocationOperation alloc] initWithTarget:self selector:@selector(saveMetadata) object:nil];
            [self.queue addOperation:io];
        }
    }
    return cachedResponse;
}

#pragma mark -
#pragma mark Private, Custom Cache Methods

- (BOOL)shouldStoreCachedResponse:(NSCachedURLResponse *)response forRequest:(NSURLRequest *)request {
    
    NSString *referer = [[request allHTTPHeaderFields] objectForKey:@"Referer"];
    BOOL whitelisted = [self.resourceTypes containsObject:response.response.MIMEType];
    NSString *host = request.URL.host;
    NSString  *airshipHost = [[NSURL URLWithString:[UAirship shared].config.deviceAPIURL] host];
    
    //only cache responses to requests for content from the airship server, 
    //or content types in the whitelist with no referer
    
    return [airshipHost isEqualToString:host] || (whitelisted && !referer);
}

- (NSString *)getStoragePathForHash:(NSString *)hash {
    return [NSString stringWithFormat:@"%@/%@", self.cacheDirectory, hash];
}

- (NSString *)getStoragePathForURL:(NSURL *)url {    
    return [self getStoragePathForHash:[UAUtils md5:[url absoluteString]]];
}

- (NSString *)getStoragePathForContentTypeWithHash:(NSString *)hash {
    return [NSString stringWithFormat:@"%@%@", [self getStoragePathForHash:hash], @".contentType"];
}

- (NSString *)getStoragePathForContentTypeWithURL:(NSURL *)url {
    return [self getStoragePathForContentTypeWithHash:[UAUtils md5:[url absoluteString]]];
}


- (void)storeContent:(NSData *)content withURL:(NSURL *)url contentType:(NSString *)contentType {
    @autoreleasepool {
    
        NSString *contentPath = [self getStoragePathForURL:url];
        NSString *contentTypePath = [self getStoragePathForContentTypeWithURL:url];
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:contentPath]) {
            UALOG(@"File exists %@", contentPath);
        }
        
        else {
            BOOL ok = [content writeToFile:contentPath atomically:YES];
            UALOG(@"Caching %@ at %@: %@", [url absoluteString], contentPath, ok?@"OK":@"FAILED");
            
            if (ok) {
                NSString *hash = [UAUtils md5:[url absoluteString]];
                
                @synchronized(self.metadata) {
                    [[self.metadata objectForKey:SIZES_KEY] setValue:[NSNumber numberWithUnsignedInt:content.length] forKey:hash];
                    [[self.metadata objectForKey:ACCESS_KEY] setValue:[NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970]] forKey:hash];
                    
                    
                    NSUInteger currentSize = [[self.metadata objectForKey:CACHE_SIZE_KEY] unsignedIntValue];
                    currentSize += content.length;
                    [self.metadata setValue:[NSNumber numberWithUnsignedInt:currentSize] forKey:CACHE_SIZE_KEY];
                    
                    UALOG(@"Cache size: %d bytes", currentSize);
                    UALOG(@"Actual disk capacity: %d bytes", self.actualDiskCapacity);
                    
                    if (currentSize > self.actualDiskCapacity) {
                        [self purge];
                    }
                    
                    [self saveMetadata];
                }
            }
            
            ok = [contentType writeToFile:contentTypePath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            UALOG(@"Caching %@ at %@: %@", contentType, contentTypePath, ok?@"OK":@"FAILED");
        }
    
    }
}

- (NSArray *)mimeTypeAndCharsetForContentType:(NSString *)contentType {
   
    NSRange range = [contentType rangeOfString:@"charset="];
    
    NSString *contentSubType;
    NSString *charset;

    if (!contentType) {
        return nil;
    }

    if (range.location != NSNotFound) {
        contentSubType = [[[contentType substringToIndex:range.location] stringByReplacingOccurrencesOfString:@";" withString:@""]
                     stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        charset = [[contentType substringFromIndex:(range.location + range.length)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        return @[contentSubType, charset];
    }
    
    else {
        return @[contentType];
    }    
}

//housekeeping

- (NSString *)getMetadataPath {
    return [NSString stringWithFormat:@"%@/%@", self.cacheDirectory, METADATA_NAME];
}

- (NSMutableDictionary *)loadMetadata {
    NSString *metadataPath = [self getMetadataPath];
    NSMutableDictionary *dict = nil;
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:metadataPath]) {
        //if this fails, dict will remain nil
        dict = [NSMutableDictionary dictionaryWithContentsOfFile:metadataPath];
    }
    
    if (!dict) {
        dict = [NSMutableDictionary dictionary];
        [dict setValue:[NSNumber numberWithUnsignedInt:0] forKey:CACHE_SIZE_KEY];
        [dict setValue:[NSMutableDictionary dictionary] forKey:SIZES_KEY];
        [dict setValue:[NSMutableDictionary dictionary] forKey:ACCESS_KEY];
    }
    
    return dict;
}

- (void)saveMetadata {
    @autoreleasepool {
        @synchronized(self.metadata) {
            if (self.metadata) {
                NSString *metadataPath = [self getMetadataPath];
                [self.metadata writeToFile:metadataPath atomically:YES];
            }
        }
    }
}

- (NSUInteger)deleteCacheEntry:(NSString *)hash {
    UALOG(@"Deleting cache entry for %@", hash);
    NSString *contentPath = [self getStoragePathForHash:hash];
    NSString *contentTypePath = [self getStoragePathForContentTypeWithHash:hash];
    
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    [fileManager removeItemAtPath:contentPath error:NULL];
    [fileManager removeItemAtPath:contentTypePath error:NULL];
    
    NSUInteger currentSize = [[self.metadata objectForKey:CACHE_SIZE_KEY] unsignedIntValue];
    NSUInteger contentSize = [[[self.metadata objectForKey:SIZES_KEY] objectForKey:hash] unsignedIntValue];
    currentSize -= contentSize;
    
    [self.metadata setValue:[NSNumber numberWithUnsignedInt:currentSize] forKey:CACHE_SIZE_KEY];
    
    [[self.metadata objectForKey:SIZES_KEY] removeObjectForKey:hash];
    [[self.metadata objectForKey:ACCESS_KEY] removeObjectForKey:hash];
    
    return currentSize;
}

- (void)purge {
    UALOG(@"Purge");
    NSUInteger currentSize = [[self.metadata objectForKey:CACHE_SIZE_KEY] unsignedIntValue];
    UALOG(@"Cache size before purge: %d bytes", currentSize);
    if (currentSize <= self.actualDiskCapacity) {
        //nothing to do here
        return;
    } else {
        int delta = 0;
        NSArray *sortedHashes = [[self.metadata objectForKey:ACCESS_KEY] keysSortedByValueUsingSelector:@selector(compare:)];
        
        for (NSString *hash in sortedHashes) {
            currentSize = [self deleteCacheEntry:hash];
            delta = currentSize - self.actualDiskCapacity;
            if (delta <= 0) {
                break;
            }
        }
    
        UALOG(@"Cache size after purge: %d bytes", currentSize);
    }
}

@end


