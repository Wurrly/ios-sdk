#import "CleverSDK.h"

@interface CleverSDK ()

@property (nonatomic, strong) NSString *clientId;
@property (nonatomic, strong) NSString *redirectUri;

@property (nonatomic, strong) NSString *state;
@property (atomic, assign) BOOL alreadyMissedCode;

@property (nonatomic, copy) void (^loginHandler)(NSURL *);
@property (nonatomic, copy) void (^successHandler)(NSString *, BOOL);
@property (nonatomic, copy) void (^failureHandler)(NSString *);

+ (instancetype)sharedManager;

@end

@implementation CleverSDK

+ (instancetype)sharedManager {
    static CleverSDK *_sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedManager = [[self alloc] init];
    });
    return _sharedManager;
}

+ (void)startWithClientId:(NSString * _Nonnull)clientId
              RedirectURI:(NSString * _Nonnull)redirectUri
             loginHandler:(void (^_Nonnull)(NSURL * _Nonnull url))loginHandler
           successHandler:(void (^_Nonnull)(NSString * _Nonnull code, BOOL validState))successHandler
           failureHandler:(void (^_Nonnull)(NSString * _Nonnull errorMessage))failureHandler {
    CleverSDK *manager = [self sharedManager];
    manager.clientId = clientId;
    manager.alreadyMissedCode = NO;
    manager.redirectUri = redirectUri;
    manager.loginHandler = loginHandler;
    manager.successHandler = successHandler;
    manager.failureHandler = failureHandler;
}

+ (NSString *)generateRandomString:(int)length {
    NSAssert(length % 2 == 0, @"Must generate random string with even length");

    NSMutableData *data = [NSMutableData dataWithLength:length / 2];
    int errorCode __unused = SecRandomCopyBytes(kSecRandomDefault, length, [data mutableBytes]);
    NSAssert(errorCode == 0, @"Failure in SecRandomCopyBytes: %d", errorCode);

    NSMutableString *hexString  = [NSMutableString stringWithCapacity:(length)];
    const unsigned char *dataBytes = [data bytes];
    for (int i = 0; i < length / 2; ++i)
    {
        [hexString appendFormat:@"%02x", (unsigned int)dataBytes[i]];
    }

    return [NSString stringWithString:hexString];
}

+ (void)login {
    [self loginWithDistrictId:nil];
}

+ (void)loginWithDistrictId:(NSString * _Nullable)districtId {
    CleverSDK *manager = [self sharedManager];
    manager.state = [self generateRandomString:32];
    
    NSString *webURLString = [NSString stringWithFormat:@"https://clever.com/oauth/authorize?response_type=code&client_id=%@&redirect_uri=%@&state=%@&redo_login=true&confirmed=false", manager.clientId, manager.redirectUri, manager.state];
    
    if (districtId != nil) {
        webURLString = [NSString stringWithFormat:@"%@&district_id=%@", webURLString, districtId];
    }

    manager.loginHandler([NSURL URLWithString:webURLString]);
}

+ (BOOL)handleURL:(NSURL * _Nonnull)url {
    CleverSDK *manager = [self sharedManager];

    NSURL *redirectURL = [NSURL URLWithString:manager.redirectUri];

    if (! (
            [url.scheme isEqualToString:redirectURL.scheme] &&
            [url.host isEqualToString:redirectURL.host] &&
            [url.path isEqualToString:redirectURL.path]
    )) {
        return NO;
    }
    
    NSString *query = url.query;
    NSMutableDictionary *kvpairs = [NSMutableDictionary dictionaryWithCapacity:1];
    NSArray *components = [query componentsSeparatedByString:@"&"];
    for (NSString *component in components) {
        NSArray *kv = [component componentsSeparatedByString:@"="];
        kvpairs[kv[0]] = kv[1];
    }
    
    // if code is missing, then this is a Clever Portal initiated login, and we should kick off the Oauth flow
    NSString *code = kvpairs[@"code"];
    if (!code) {
        CleverSDK* manager = [self sharedManager];
        if (manager.alreadyMissedCode) {
            manager.alreadyMissedCode = NO;
            manager.failureHandler([NSString localizedStringWithFormat:@"Authorization failed. Please try logging in again."]);
            return YES;
        }
        manager.alreadyMissedCode = YES;
        [self login];
        return YES;
    }
    
    BOOL validState = NO;
    
    NSString *state = kvpairs[@"state"];
    if ([state isEqualToString:manager.state]) {
        validState = YES;
    }
    
    manager.successHandler(code, validState);
    return YES;
}

@end
