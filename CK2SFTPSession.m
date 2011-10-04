//
//  CK2SFTPSession.m
//  Sandvox
//
//  Created by Mike on 03/07/2011.
//  Copyright 2011 Karelia Software. All rights reserved.
//

#import "CK2SFTPSession.h"

#import "CK2SFTPFileHandle.h"
#import "CK2SSHCredential.h"

#include <libssh2_sftp.h>
#include <libssh2.h>

#ifdef HAVE_SYS_SOCKET_H
# include <sys/socket.h>
#endif
#ifdef HAVE_NETINET_IN_H
# include <netinet/in.h>
#endif
#ifdef HAVE_SYS_SELECT_H
# include <sys/select.h>
#endif
# ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif
# include <arpa/inet.h>
#ifdef HAVE_SYS_TIME_H
# include <sys/time.h>
#endif

#include <sys/time.h>
#include <sys/types.h>
#include <stdlib.h>
#include <fcntl.h>
#include <errno.h>
#include <stdio.h>
#include <ctype.h>

#import <Connection/Connection.h>
#import "KTURLCredentialStorage.h"


NSString *const CK2LibSSH2ErrorDomain = @"org.libssh2.libssh2";
NSString *const CK2LibSSH2SFTPErrorDomain = @"org.libssh2.libssh2.sftp";


@interface CK2SFTPSession ()
- (void)failWithError:(NSError *)error;
- (void)startAuthentication;
@end



@implementation CK2SFTPSession

static int waitsocket(int socket_fd, LIBSSH2_SESSION *session)
{
    struct timeval timeout;
    int rc;
    fd_set fd;
    fd_set *writefd = NULL;
    fd_set *readfd = NULL;
    int dir;
    
    timeout.tv_sec = 10;
    timeout.tv_usec = 0;
    
    FD_ZERO(&fd);
    
    FD_SET(socket_fd, &fd);
    
    /* now make sure we wait in the correct direction */
    dir = libssh2_session_block_directions(session);
    
    if(dir & LIBSSH2_SESSION_BLOCK_INBOUND)
        readfd = &fd;
    
    if(dir & LIBSSH2_SESSION_BLOCK_OUTBOUND)
        writefd = &fd;
    
    rc = select(socket_fd + 1, readfd, writefd, NULL, &timeout);
    
    return rc;
}

- (NSInteger)portForURL:(NSURL *)URL;
{
    NSNumber *result = [URL port];
    return (result ? [result integerValue] : 22);
}

#pragma mark Lifecycle

- (id)initWithURL:(NSURL *)URL delegate:(id <CK2SFTPSessionDelegate>)delegate;
{
    return [self initWithURL:URL delegate:delegate startImmediately:YES];
}

- (id)initWithURL:(NSURL *)URL delegate:(id <CK2SFTPSessionDelegate>)delegate startImmediately:(BOOL)startImmediately;
{
    NSParameterAssert(URL);
    
    if (self = [self init])
    {
        _URL = [URL copy];
        _delegate = delegate;
    }
    
    if (startImmediately) [self start];
    
    return self;
}

- (void)start;
{
    if (_session) return;   // already started
    
    
    // Header
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *transcriptHeader = [NSString stringWithFormat:
                                  @"%@ %@ (architecture unknown) Session Transcript [%@] (%@)",
                                  [bundle objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey],
                                  [bundle objectForInfoDictionaryKey:(NSString *)kCFBundleVersionKey],
                                  [[NSProcessInfo processInfo] operatingSystemVersionString],
                                  [NSDate date]];
    [_delegate SFTPSession:self appendStringToTranscript:transcriptHeader];
    
    
    unsigned long hostaddr;
    struct sockaddr_in sin;
    int rc;
#if defined(HAVE_IOCTLSOCKET)
    long flag = 1;
#endif
    
    
    /* Create a session instance */
    _session = libssh2_session_init();
    if (!_session)
    {
        NSError *error = [NSError errorWithDomain:CK2LibSSH2ErrorDomain
                                             code:0
                                         userInfo:[NSDictionary dictionaryWithObject:@"libssh2 session initialization failed"
                                                                              forKey:NSLocalizedDescriptionKey]];
        
        return [self failWithError:error];
    }
    
    
    /*
     * The application code is responsible for creating the socket
     * and establishing the connection
     */
    // FIXME: NSHost is not threadsafe; use CF-level API instead
    NSString *hostName = [_URL host];
    
    [_delegate SFTPSession:self
  appendStringToTranscript:[NSString stringWithFormat:@"Connecting to %@", hostName]];
    
    NSHost *host = [NSHost hostWithName:hostName];
    NSString *address = [host address];
    if (!address)
    {
        NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                             code:NSURLErrorCannotFindHost
                                         userInfo:[NSDictionary dictionaryWithObject:@"Cannot find host"
                                                                              forKey:NSLocalizedDescriptionKey]];
        
        return [self failWithError:error];
    }
    
    hostaddr = inet_addr([address UTF8String]);
    
    _socket = CFSocketCreate(NULL, AF_INET, SOCK_STREAM, 0, 0, NULL, NULL);
    if (!_socket)
    {
        NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                             code:NSURLErrorUnknown
                                         userInfo:[NSDictionary dictionaryWithObject:@"Error creating socket"
                                                                              forKey:NSLocalizedDescriptionKey]];
        
        return [self failWithError:error];
    }
    
    sin.sin_family = AF_INET;
    sin.sin_port = htons([self portForURL:_URL]);
    sin.sin_addr.s_addr = hostaddr;
    
    CFDataRef addressData = CFDataCreate(NULL, (UInt8 *)&sin, sizeof(struct sockaddr_in));
    CFSocketError socketError = CFSocketConnectToAddress(_socket, addressData, 60.0);
    CFRelease(addressData);
    
    if (socketError != kCFSocketSuccess)
    {
        NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                             code:NSURLErrorCannotConnectToHost
                                         userInfo:[NSDictionary dictionaryWithObject:@"Cannot connect to host"
                                                                              forKey:NSLocalizedDescriptionKey]];
        
        return [self failWithError:error];
    }
    
    
    /* Since we have set non-blocking, tell libssh2 we are non-blocking */
    //libssh2_session_set_blocking(_session, 0);
    
    
    /* ... start it up. This will trade welcome banners, exchange keys,
     * and setup crypto, compression, and MAC layers
     */
    while ((rc = libssh2_session_startup(_session, CFSocketGetNative(_socket))) ==
           LIBSSH2_ERROR_EAGAIN);
    if (rc)
    {
        return [self failWithError:[self sessionError]];
    }
    
    
    /* At this point we havn't yet authenticated.  The first thing to do
     * is check the hostkey's fingerprint against our known hosts Your app
     * may have it hard coded, may go to a file, may present it to the
     * user, that's your call
     */
    const char *fingerprint = libssh2_hostkey_hash(_session, LIBSSH2_HOSTKEY_HASH_SHA1);
    
    [_delegate SFTPSession:self appendStringToTranscript:
     [NSString stringWithFormat:
      @"Fingerprint: %@",
      [NSData dataWithBytes:fingerprint length:20]]];   // SHA1 hashes are 20bytes
    
    
    [self startAuthentication];
}

- (void)cancel;
{
    _delegate = nil;
    
    [_URL release]; _URL = nil;
    
    libssh2_sftp_shutdown(_sftp); _sftp = NULL;
    
    
    BOOL logged = NO;
    if (_session)
    {
        [_delegate SFTPSession:self appendStringToTranscript:@"Disconnecting from server…"];
        logged = YES;
        
        libssh2_session_disconnect(_session, "Normal Shutdown, Thank you");
        libssh2_session_free(_session); _session = NULL;
    }
    
    if (_socket)
    {
        if (!logged) [_delegate SFTPSession:self appendStringToTranscript:@"Disconnecting from server…"];
        
        CFSocketInvalidate(_socket);
        CFRelease(_socket); _socket = NULL;
    }
    
    libssh2_exit();
}

- (void)dealloc
{
    [self cancel];
    
    OBASSERT(!_URL);
    OBASSERT(!_sftp);
    OBASSERT(!_session);
    OBASSERT(!_socket);
    
    [super dealloc];
}

#pragma mark Error Handling

- (NSError *)sessionErrorWithPath:(NSString *)path;
{
    char *errormsg;
    int code = libssh2_session_last_error(_session, &errormsg, NULL, 0);
    if (code == 0) return nil;
    
    NSString *description = [[NSString alloc] initWithCString:errormsg encoding:NSUTF8StringEncoding];
    
    NSError *result = [NSError errorWithDomain:CK2LibSSH2ErrorDomain
                                          code:code
                                      userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                                description,
                                                NSLocalizedDescriptionKey,
                                                path,
                                                NSFilePathErrorKey,
                                                nil]];
    [description release];
    
    
    if (code == LIBSSH2_ERROR_SFTP_PROTOCOL)
    {
        code = libssh2_sftp_last_error(_sftp);
        
        result = [NSError errorWithDomain:CK2LibSSH2SFTPErrorDomain
                                     code:code
                                 userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                           result,
                                           NSUnderlyingErrorKey,
                                           path,
                                           NSFilePathErrorKey,
                                           nil]];
    }
    
    return result;
}

- (NSError *)sessionError;
{
    return [self sessionErrorWithPath:nil];
}

- (void)failWithError:(NSError *)error
{
    id delegate = _delegate;    // because -cancel will set it to nil
    [self cancel];
    [delegate SFTPSession:self didFailWithError:error];
}

#pragma mark Directories

- (BOOL)createDirectoryAtPath:(NSString *)path mode:(long)mode error:(NSError **)error;
{
    int result = libssh2_sftp_mkdir(_sftp, [path UTF8String], mode);
    
    if (result == 0)
    {
        return YES;
    }
    else
    {
        if (error) *error = [self sessionErrorWithPath:path];
        return NO;
    }
}

- (BOOL)createDirectoryAtPath:(NSString *)path withIntermediateDirectories:(BOOL)createIntermediates mode:(long)mode error:(NSError **)outError;
{
    if (!createIntermediates) return [self createDirectoryAtPath:path mode:mode error:outError];
    
    NSError *error;
    BOOL result = [self createDirectoryAtPath:path mode:mode error:&error];
    
    if (!result)
    {
        if (outError) *outError = error;
        
        if ([[error domain] isEqualToString:CK2LibSSH2SFTPErrorDomain] && [error code] == LIBSSH2_FX_NO_SUCH_FILE)
        {
            if ([self createDirectoryAtPath:[path stringByDeletingLastPathComponent]
                withIntermediateDirectories:createIntermediates
                                       mode:mode
                                      error:outError])
            {
                result = [self createDirectoryAtPath:path mode:mode error:outError];
            }
        }
    }
    
    return result;
}

#pragma mark Files

- (CK2SFTPFileHandle *)openHandleAtPath:(NSString *)path flags:(unsigned long)flags mode:(long)mode error:(NSError **)error;
{
    NSParameterAssert(path);
    
    [_delegate SFTPSession:self
  appendStringToTranscript:[NSString stringWithFormat:@"Uploading file %@", [path lastPathComponent]]];
    
    LIBSSH2_SFTP_HANDLE *handle = libssh2_sftp_open(_sftp, [path UTF8String], flags, mode);
    
    if (!handle)
    {
        if (error) *error = [self sessionErrorWithPath:path];
        return nil;
    }
    
    return [[[CK2SFTPFileHandle alloc] initWithSFTPHandle:handle session:self path:path] autorelease];
}

- (BOOL)removeFileAtPath:(NSString *)path error:(NSError **)error;
{
    NSParameterAssert(path);
    
    [_delegate SFTPSession:self
  appendStringToTranscript:[NSString stringWithFormat:@"Deleting file %@", [path lastPathComponent]]];
    
    int result = libssh2_sftp_unlink(_sftp, [path UTF8String]);
    
    if (result == 0)
    {
        return YES;
    }
    else
    {
        if (error) *error = [self sessionErrorWithPath:path];
        return NO;
    }
}

#pragma mark Auth

- (void)startAuthentication;
{
    /* We could authenticate via password */
    NSURLProtectionSpace *protectionSpace = [[CKURLProtectionSpace alloc] initWithHost:[_URL host]
                                                                                  port:[self portForURL:_URL]
                                                                              protocol:@"ssh"
                                                                                 realm:nil
                                                                  authenticationMethod:NSURLAuthenticationMethodDefault];
    
    _challenge = [[NSURLAuthenticationChallenge alloc]
                  initWithProtectionSpace:protectionSpace
                  proposedCredential:nil
                  previousFailureCount:0
                  failureResponse:nil
                  error:nil
                  sender:self];
    [protectionSpace release];
    
    [_delegate SFTPSession:self didReceiveAuthenticationChallenge:_challenge];        
}

- (void)initializeSFTP;
{
    do {
        _sftp = libssh2_sftp_init(_session);
        
        if (!_sftp)
        {
            int lastErrNo = libssh2_session_last_errno(_session);
            
            if (lastErrNo == LIBSSH2_ERROR_EAGAIN)
            {
                waitsocket(CFSocketGetNative(_socket), _session); /* now we wait */
            }
            else
            {
                [self failWithError:[self sessionError]];
                return;
            }
        }
    } while (!_sftp);
    
    [_delegate SFTPSessionDidInitialize:self];
}

- (BOOL)usePublicKeyCredential:(NSURLCredential *)credential;
{
    NSString *privateKey = [[credential ck2_privateKeyURL] path];
    NSString *publicKey = [[credential ck2_publicKeyURL] path];
    
    if (!privateKey && !publicKey)
    {
        LIBSSH2_AGENT *agent = libssh2_agent_init(_session);
        if (!agent)
        {
            return NO;
        }
        
        if (libssh2_agent_connect(agent) != LIBSSH2_ERROR_NONE)
        {
            libssh2_agent_free(agent);
            return NO;
        }
        
        if (libssh2_agent_list_identities(agent) != LIBSSH2_ERROR_NONE)
        {
            [_delegate SFTPSession:self appendStringToTranscript:@"Failed to list identities from SSH Agent"];
            libssh2_agent_free(agent);
            return NO;
        }
        
        struct libssh2_agent_publickey *identity = NULL;
        while (YES)
        {
            if (libssh2_agent_get_identity(agent, &identity, identity) != LIBSSH2_ERROR_NONE)
            {
                libssh2_agent_disconnect(agent);
                libssh2_agent_free(agent);
                return NO;
            }
            
            if (libssh2_agent_userauth(agent, [[credential user] UTF8String], identity) == LIBSSH2_ERROR_NONE)
            {
                break;
            }
            
            // Log each rejected key
            [_delegate SFTPSession:self appendStringToTranscript:
             [NSString stringWithFormat:
              @"%@ (%@)",
              [[self sessionError] localizedDescription],
              [NSString stringWithUTF8String:(*identity).comment]]];
        }
        
        libssh2_agent_disconnect(agent);
        libssh2_agent_free(agent); agent = NULL;
        
        [self initializeSFTP];
    }
    else
    {
        int result = libssh2_userauth_publickey_fromfile(_session,
                                                         [[credential user] UTF8String],
                                                         [publicKey fileSystemRepresentation],
                                                         [privateKey fileSystemRepresentation],
                                                         NULL);
        if (result)
        {
            return NO;
        }
        
        [self initializeSFTP];
    }
    
    return YES;
}

- (void)useCredential:(NSURLCredential *)credential forAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    NSParameterAssert(challenge);
    NSParameterAssert(challenge == _challenge);
    [_challenge autorelease]; _challenge = nil; // autorelease so can use for duration of method
    
    
    if ([credential ck2_isPublicKeyCredential])
    {
        if (![self usePublicKeyCredential:credential])
        {
            _challenge = [[NSURLAuthenticationChallenge alloc]
                          initWithProtectionSpace:[challenge protectionSpace]
                          proposedCredential:credential
                          previousFailureCount:([challenge previousFailureCount] + 1)
                          failureResponse:nil
                          error:[self sessionError]
                          sender:self];
            
            [_delegate SFTPSession:self didReceiveAuthenticationChallenge:_challenge];
        }
    }
    else
    {
        NSString *username = [credential user];
        NSString *password = [credential password];
        
        int rc;
        while ((rc = libssh2_userauth_password(_session, [username UTF8String], [password UTF8String]))
               == LIBSSH2_ERROR_EAGAIN);
        
        if (rc)
        {
            NSError *error = [self sessionError];
            
            _challenge = [[NSURLAuthenticationChallenge alloc]
                          initWithProtectionSpace:[challenge protectionSpace]
                          proposedCredential:credential
                          previousFailureCount:([challenge previousFailureCount] + 1)
                          failureResponse:nil
                          error:error
                          sender:self];
            
            [_delegate SFTPSession:self didReceiveAuthenticationChallenge:_challenge];
        }
        else
        {
            [self initializeSFTP];
        }
    }
}

- (void)continueWithoutCredentialForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    NSParameterAssert(challenge);
    NSParameterAssert(challenge == _challenge);
    [_challenge release]; _challenge = nil;
    
    [self initializeSFTP];
}

- (void)cancelAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge;
{
    NSParameterAssert(challenge);
    NSParameterAssert(challenge == _challenge);
    [_challenge release]; _challenge = nil;

    [self cancel];
}

#pragma mark Low-level

@synthesize libssh2_sftp = _sftp;

@end
