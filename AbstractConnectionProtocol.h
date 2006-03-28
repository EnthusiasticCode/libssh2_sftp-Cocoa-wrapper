/*
 
 AbstractConnectionProtocol.h
 Marvel
 
 Copyright (c) 2004-2005 Biophony LLC. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Biophony LLC nor the names of its contributors may be used to 
 endorse or promote products derived from this software without specific prior 
 written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY 
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT 
 SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED 
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
 BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY 
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
 */
#import <Cocoa/Cocoa.h>

// Some shared Error Codes

enum {
	ConnectionErrorUploading = 49101,
	ConnectionErrorDownloading,
	ConnectionErrorCreatingDirectory
};

typedef struct __flags {
	unsigned isConnected:1;
	
	// There are 21 callbacks & flags.
	// Need to keep NSObject Category, __flags list, setDelegate: updated
	
	unsigned permissions:1;
	unsigned badPassword:1;
	unsigned cancel:1;
	unsigned changeDirectory:1;
	unsigned createDirectory:1;
	unsigned deleteDirectory:1;
	unsigned deleteFile:1;
	unsigned didBeginUpload:1;
	unsigned didConnect:1;
	unsigned didDisconnect:1;
	unsigned directoryContents:1;
	unsigned didBeginDownload:1;
	unsigned downloadFinished:1;
	unsigned downloadPercent:1;
	unsigned downloadProgressed:1;
	unsigned error:1;
	unsigned needsAccount:1;
	unsigned rename:1;
	unsigned uploadFinished:1;
	unsigned uploadPercent:1;
	unsigned uploadProgressed:1;
	unsigned directoryContentsStreamed:1;
	unsigned inBulk:1;
	unsigned fileCheck:1;
	unsigned authorizeConnection:1;
	
	unsigned padding:6;
	
} connectionFlags;


@protocol AbstractConnectionProtocol

+ (NSString *)name;


+ (id)connectionToHost:(NSString *)host
				  port:(NSString *)port
			  username:(NSString *)username
			  password:(NSString *)password;

+ (id)connectionWithURL:(NSURL *)url;

+ (id)connectionWithName:(NSString *)name
					host:(NSString *)host
					port:(NSString *)port
				username:(NSString *)username
				password:(NSString *)password;

- (id)initWithHost:(NSString *)host
			  port:(NSString *)port
		  username:(NSString *)username
		  password:(NSString *)password;

- (void)setHost:(NSString *)host;
- (void)setPort:(NSString *)port;
- (void)setUsername:(NSString *)username;
- (void)setPassword:(NSString *)password;

- (NSString *)host;
- (NSString *)port;
- (NSString *)username;
- (NSString *)password;

- (void)setDelegate:(id)delegate;   // we do not retain the delegate
- (id)delegate;

- (void)connect;
- (BOOL)isConnected;

/* disconnect queues a disconnection where as forceDisconnect '
   will terminate at the next available opportunity. */
- (void)disconnect;
- (void)forceDisconnect;

- (void)changeToDirectory:(NSString *)dirPath;
- (NSString *)currentDirectory;

- (NSString *)rootDirectory;
- (void)createDirectory:(NSString *)dirPath;
- (void)createDirectory:(NSString *)dirPath permissions:(unsigned long)permissions;
- (void)setPermissions:(unsigned long)permissions forFile:(NSString *)path;

- (void)rename:(NSString *)fromPath to:(NSString *)toPath;
- (void)deleteFile:(NSString *)path;
- (void)deleteDirectory:(NSString *)dirPath;

- (void)startBulkCommands;
- (void)endBulkCommands;

- (void)uploadFile:(NSString *)localPath;
- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath;
- (void)uploadFile:(NSString *)localPath toFile:(NSString *)remotePath checkRemoteExistence:(BOOL)flag;

- (void)resumeUploadFile:(NSString *)localPath fileOffset:(long long)offset;
- (void)resumeUploadFile:(NSString *)localPath toFile:(NSString *)remotePath fileOffset:(long long)offset;

- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath;
- (void)uploadFromData:(NSData *)data toFile:(NSString *)remotePath checkRemoteExistence:(BOOL)flag;

- (void)resumeUploadFromData:(NSData *)data toFile:(NSString *)remotePath fileOffset:(long long)offset;

- (void)downloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath overwrite:(BOOL)flag;
- (void)resumeDownloadFile:(NSString *)remotePath toDirectory:(NSString *)dirPath fileOffset:(long long)offset;

- (unsigned)numberOfTransfers;
- (void)cancelTransfer;
- (void)cancelAll;

- (void)directoryContents;
- (void)contentsOfDirectory:(NSString *)dirPath;

- (long long)transferSpeed; // bytes/second

- (void)checkExistenceOfPath:(NSString *)path;

@end



@interface NSObject (AbstractConnectionDelegate)

// There are 21 callbacks & flags.
// Need to keep NSObject Category, __flags list, setDelegate: updated

- (void)connection:(id <AbstractConnectionProtocol>)con didChangeToDirectory:(NSString *)dirPath;
- (BOOL)connection:(id <AbstractConnectionProtocol>)con authorizeConnectionToHost:(NSString *)host message:(NSString *)message;
- (void)connection:(id <AbstractConnectionProtocol>)con didConnectToHost:(NSString *)host;
- (void)connection:(id <AbstractConnectionProtocol>)con didCreateDirectory:(NSString *)dirPath;
- (void)connection:(id <AbstractConnectionProtocol>)con didDeleteDirectory:(NSString *)dirPath;
- (void)connection:(id <AbstractConnectionProtocol>)con didDeleteFile:(NSString *)path;
- (void)connection:(id <AbstractConnectionProtocol>)con didDisconnectFromHost:(NSString *)host;
- (void)connection:(id <AbstractConnectionProtocol>)con didReceiveContents:(NSArray *)contents ofDirectory:(NSString *)dirPath;
- (void)connection:(id <AbstractConnectionProtocol>)con didReceiveContents:(NSArray *)contents ofDirectory:(NSString *)dirPath moreComing:(BOOL)flag;
- (void)connection:(id <AbstractConnectionProtocol>)con didReceiveError:(NSError *)error;
- (void)connection:(id <AbstractConnectionProtocol>)con didRename:(NSString *)fromPath to:(NSString *)toPath;
- (void)connection:(id <AbstractConnectionProtocol>)con didSetPermissionsForFile:(NSString *)path;
- (void)connection:(id <AbstractConnectionProtocol>)con download:(NSString *)path progressedTo:(NSNumber *)percent;
- (void)connection:(id <AbstractConnectionProtocol>)con download:(NSString *)path receivedDataOfLength:(unsigned long long)length; 
- (void)connection:(id <AbstractConnectionProtocol>)con downloadDidBegin:(NSString *)remotePath;
- (void)connection:(id <AbstractConnectionProtocol>)con downloadDidFinish:(NSString *)remotePath;
- (NSString *)connection:(id <AbstractConnectionProtocol>)con needsAccountForUsername:(NSString *)username;
- (void)connection:(id <AbstractConnectionProtocol>)con upload:(NSString *)remotePath progressedTo:(NSNumber *)percent;
- (void)connection:(id <AbstractConnectionProtocol>)con upload:(NSString *)remotePath sentDataOfLength:(unsigned long long)length;
- (void)connection:(id <AbstractConnectionProtocol>)con uploadDidBegin:(NSString *)remotePath;
- (void)connection:(id <AbstractConnectionProtocol>)con uploadDidFinish:(NSString *)remotePath;
- (void)connectionDidCancelTransfer:(id <AbstractConnectionProtocol>)con;
- (void)connectionDidSendBadPassword:(id <AbstractConnectionProtocol>)con;
- (void)connection:(id <AbstractConnectionProtocol>)con checkedExistenceOfPath:(NSString *)path pathExists:(BOOL)exists;
@end

//registration type dictionary keys
extern NSString *ACTypeKey;
extern NSString *ACTypeValueKey;
extern NSString *ACPortTypeKey;
extern NSString *ACURLTypeKey; /* ftp://, http://, etc */

// Attributes for which there isn't a corresponding NSFileManager key
extern NSString *cxFilenameKey;
extern NSString *cxSymbolicLinkTargetKey;

//User Info Keys for Errors
extern NSString *ConnectionDirectoryExistsKey;
extern NSString *ConnectionDirectoryExistsFilenameKey;

/*
 * The InputStream and OutputStream protocols, provides a transparent way to interchange
 * the implementation specific streams.
 */
@protocol InputStream <NSObject>
- (void)open;
- (void)close;
- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;
- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;
- (void)setDelegate:(id)delegate;
- (id)delegate;
- (BOOL)setProperty:(id)property forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
- (NSError *)streamError;
- (NSStreamStatus)streamStatus;

- (int)read:(uint8_t *)buffer maxLength:(unsigned int)len;
@end

@protocol OutputStream <NSObject>
- (void)open;
- (void)close;
- (void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;
- (void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString *)mode;
- (void)setDelegate:(id)delegate;
- (id)delegate;
- (BOOL)setProperty:(id)property forKey:(NSString *)key;
- (id)propertyForKey:(NSString *)key;
- (NSError *)streamError;
- (NSStreamStatus)streamStatus;

- (int)write:(const uint8_t *)buffer maxLength:(unsigned int)len;
@end