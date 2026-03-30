//
//  FCPBridgeServer.m
//  JSON-RPC 2.0 server over Unix domain socket
//

#import "FCPBridge.h"
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/stat.h>
#import <netinet/in.h>
#import <arpa/inet.h>

#define FCPBRIDGE_TCP_PORT 9876

#pragma mark - Client Management

static NSMutableArray *sConnectedClients = nil;
static dispatch_queue_t sClientQueue = nil;

void FCPBridge_broadcastEvent(NSDictionary *event) {
    if (!sConnectedClients || !sClientQueue) return;

    NSMutableDictionary *notification = [NSMutableDictionary dictionaryWithDictionary:@{
        @"jsonrpc": @"2.0",
        @"method": @"event",
        @"params": event
    }];

    NSData *json = [NSJSONSerialization dataWithJSONObject:notification options:0 error:nil];
    if (!json) return;

    NSMutableData *line = [json mutableCopy];
    [line appendBytes:"\n" length:1];

    dispatch_async(sClientQueue, ^{
        NSArray *clients = [sConnectedClients copy];
        for (NSNumber *fd in clients) {
            write([fd intValue], line.bytes, line.length);
        }
    });
}

#pragma mark - Request Handler

static NSDictionary *FCPBridge_handleSystemGetClasses(NSDictionary *params) {
    NSString *filter = params[@"filter"];
    NSArray *allClasses = FCPBridge_allLoadedClasses();

    if (filter && filter.length > 0) {
        NSPredicate *predicate = [NSPredicate predicateWithFormat:
                                  @"SELF CONTAINS[cd] %@", filter];
        allClasses = [allClasses filteredArrayUsingPredicate:predicate];
    }

    return @{@"classes": allClasses, @"count": @(allClasses.count)};
}

static NSDictionary *FCPBridge_handleSystemGetMethods(NSDictionary *params) {
    NSString *className = params[@"className"];
    if (!className) return @{@"error": @"className required"};

    Class cls = objc_getClass([className UTF8String]);
    if (!cls) return @{@"error": [NSString stringWithFormat:@"Class %@ not found", className]};

    BOOL includeSuper = [params[@"includeSuper"] boolValue];
    NSMutableDictionary *allMethods = [NSMutableDictionary dictionary];

    Class current = cls;
    while (current) {
        NSDictionary *methods = FCPBridge_methodsForClass(current);
        [allMethods addEntriesFromDictionary:methods];
        if (!includeSuper) break;
        current = class_getSuperclass(current);
        if (current == [NSObject class]) break;
    }

    // Also get class methods
    NSMutableDictionary *classMethods = [NSMutableDictionary dictionary];
    Class metaCls = object_getClass(cls);
    if (metaCls) {
        unsigned int count = 0;
        Method *methodList = class_copyMethodList(metaCls, &count);
        if (methodList) {
            for (unsigned int i = 0; i < count; i++) {
                SEL sel = method_getName(methodList[i]);
                NSString *name = NSStringFromSelector(sel);
                const char *types = method_getTypeEncoding(methodList[i]);
                classMethods[name] = @{
                    @"selector": name,
                    @"typeEncoding": types ? @(types) : @"",
                    @"imp": [NSString stringWithFormat:@"0x%lx",
                             (unsigned long)method_getImplementation(methodList[i])]
                };
            }
            free(methodList);
        }
    }

    return @{
        @"className": className,
        @"instanceMethods": allMethods,
        @"classMethods": classMethods,
        @"instanceMethodCount": @(allMethods.count),
        @"classMethodCount": @(classMethods.count)
    };
}

static NSDictionary *FCPBridge_handleSystemCallMethod(NSDictionary *params) {
    NSString *className = params[@"className"];
    NSString *selectorName = params[@"selector"];
    BOOL isClassMethod = [params[@"classMethod"] boolValue];

    if (!className || !selectorName)
        return @{@"error": @"className and selector required"};

    Class cls = objc_getClass([className UTF8String]);
    if (!cls) return @{@"error": [NSString stringWithFormat:@"Class %@ not found", className]};

    SEL selector = NSSelectorFromString(selectorName);

    __block NSDictionary *result = nil;

    FCPBridge_executeOnMainThread(^{
        @try {
            id target = isClassMethod ? (id)cls : nil;

            if (!isClassMethod) {
                // For instance methods, we need an instance
                // Try common singleton patterns
                if ([cls respondsToSelector:@selector(sharedInstance)]) {
                    target = [cls performSelector:@selector(sharedInstance)];
                } else if ([cls respondsToSelector:@selector(shared)]) {
                    target = [cls performSelector:@selector(shared)];
                } else if ([cls respondsToSelector:@selector(defaultManager)]) {
                    target = [cls performSelector:@selector(defaultManager)];
                } else {
                    result = @{@"error": @"Cannot get instance. Use classMethod:true or provide an instance path"};
                    return;
                }
            }

            if (!target) {
                result = @{@"error": @"Target is nil"};
                return;
            }

            if (![target respondsToSelector:selector]) {
                result = @{@"error": [NSString stringWithFormat:@"%@ does not respond to %@",
                                      className, selectorName]};
                return;
            }

            // Get method signature for return type analysis
            NSMethodSignature *sig = isClassMethod
                ? [cls methodSignatureForSelector:selector]
                : [target methodSignatureForSelector:selector];
            const char *returnType = [sig methodReturnType];

            id returnValue = nil;

            // Handle based on return type
            if (returnType[0] == 'v') {
                // void return
                ((void (*)(id, SEL))objc_msgSend)(target, selector);
                result = @{@"result": @"void"};
            } else if (returnType[0] == 'B' || returnType[0] == 'c') {
                // BOOL return
                BOOL boolResult = ((BOOL (*)(id, SEL))objc_msgSend)(target, selector);
                result = @{@"result": @(boolResult)};
            } else if (returnType[0] == '@') {
                // Object return
                returnValue = ((id (*)(id, SEL))objc_msgSend)(target, selector);
                if (returnValue) {
                    result = @{
                        @"result": [returnValue description] ?: @"<nil description>",
                        @"class": NSStringFromClass([returnValue class])
                    };
                } else {
                    result = @{@"result": [NSNull null]};
                }
            } else if (returnType[0] == 'q' || returnType[0] == 'i' || returnType[0] == 'l') {
                // Integer return
                long long intResult = ((long long (*)(id, SEL))objc_msgSend)(target, selector);
                result = @{@"result": @(intResult)};
            } else if (returnType[0] == 'd' || returnType[0] == 'f') {
                // Float/double return
                double dblResult = ((double (*)(id, SEL))objc_msgSend)(target, selector);
                result = @{@"result": @(dblResult)};
            } else {
                // Unknown type
                ((void (*)(id, SEL))objc_msgSend)(target, selector);
                result = @{@"result": @"<unknown return type>",
                           @"returnType": @(returnType)};
            }
        } @catch (NSException *exception) {
            result = @{
                @"error": [NSString stringWithFormat:@"Exception: %@ - %@",
                           exception.name, exception.reason]
            };
        }
    });

    return result;
}

static NSDictionary *FCPBridge_handleSystemVersion(NSDictionary *params) {
    NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
    return @{
        @"fcpbridge_version": @FCPBRIDGE_VERSION,
        @"fcp_version": info[@"CFBundleShortVersionString"] ?: @"unknown",
        @"fcp_build": info[@"CFBundleVersion"] ?: @"unknown",
        @"pid": @(getpid()),
        @"arch": @
#if __arm64__
            "arm64"
#else
            "x86_64"
#endif
    };
}

static NSDictionary *FCPBridge_handleSystemSwizzle(NSDictionary *params) {
    // Swizzle is more complex -- for now just report capability
    return @{@"error": @"Swizzle requires compiled IMP. Use system.callMethod for direct calls."};
}

static NSDictionary *FCPBridge_handleSystemGetProperties(NSDictionary *params) {
    NSString *className = params[@"className"];
    if (!className) return @{@"error": @"className required"};

    Class cls = objc_getClass([className UTF8String]);
    if (!cls) return @{@"error": [NSString stringWithFormat:@"Class %@ not found", className]};

    NSMutableArray *properties = [NSMutableArray array];
    unsigned int count = 0;
    objc_property_t *propList = class_copyPropertyList(cls, &count);
    if (propList) {
        for (unsigned int i = 0; i < count; i++) {
            const char *name = property_getName(propList[i]);
            const char *attrs = property_getAttributes(propList[i]);
            [properties addObject:@{
                @"name": @(name),
                @"attributes": @(attrs)
            }];
        }
        free(propList);
    }

    return @{@"className": className, @"properties": properties, @"count": @(count)};
}

static NSDictionary *FCPBridge_handleSystemGetProtocols(NSDictionary *params) {
    NSString *className = params[@"className"];
    if (!className) return @{@"error": @"className required"};

    Class cls = objc_getClass([className UTF8String]);
    if (!cls) return @{@"error": [NSString stringWithFormat:@"Class %@ not found", className]};

    NSMutableArray *protocols = [NSMutableArray array];
    unsigned int count = 0;
    Protocol * __unsafe_unretained *protoList = class_copyProtocolList(cls, &count);
    if (protoList) {
        for (unsigned int i = 0; i < count; i++) {
            [protocols addObject:@(protocol_getName(protoList[i]))];
        }
        free(protoList);
    }

    return @{@"className": className, @"protocols": protocols, @"count": @(count)};
}

static NSDictionary *FCPBridge_handleSystemGetSuperchain(NSDictionary *params) {
    NSString *className = params[@"className"];
    if (!className) return @{@"error": @"className required"};

    Class cls = objc_getClass([className UTF8String]);
    if (!cls) return @{@"error": [NSString stringWithFormat:@"Class %@ not found", className]};

    NSMutableArray *chain = [NSMutableArray array];
    Class current = cls;
    while (current) {
        [chain addObject:NSStringFromClass(current)];
        current = class_getSuperclass(current);
    }

    return @{@"className": className, @"superchain": chain};
}

static NSDictionary *FCPBridge_handleSystemGetIvars(NSDictionary *params) {
    NSString *className = params[@"className"];
    if (!className) return @{@"error": @"className required"};

    Class cls = objc_getClass([className UTF8String]);
    if (!cls) return @{@"error": [NSString stringWithFormat:@"Class %@ not found", className]};

    NSMutableArray *ivars = [NSMutableArray array];
    unsigned int count = 0;
    Ivar *ivarList = class_copyIvarList(cls, &count);
    if (ivarList) {
        for (unsigned int i = 0; i < count; i++) {
            const char *name = ivar_getName(ivarList[i]);
            const char *type = ivar_getTypeEncoding(ivarList[i]);
            [ivars addObject:@{
                @"name": name ? @(name) : @"<anon>",
                @"type": type ? @(type) : @"?"
            }];
        }
        free(ivarList);
    }

    return @{@"className": className, @"ivars": ivars, @"count": @(count)};
}

#pragma mark - Request Dispatcher

static NSDictionary *FCPBridge_handleRequest(NSDictionary *request) {
    NSString *method = request[@"method"];
    NSDictionary *params = request[@"params"] ?: @{};

    if (!method) {
        return @{@"error": @{@"code": @(-32600), @"message": @"Invalid Request: method required"}};
    }

    NSDictionary *result = nil;

    // system.* namespace
    if ([method isEqualToString:@"system.version"]) {
        result = FCPBridge_handleSystemVersion(params);
    } else if ([method isEqualToString:@"system.getClasses"]) {
        result = FCPBridge_handleSystemGetClasses(params);
    } else if ([method isEqualToString:@"system.getMethods"]) {
        result = FCPBridge_handleSystemGetMethods(params);
    } else if ([method isEqualToString:@"system.callMethod"]) {
        result = FCPBridge_handleSystemCallMethod(params);
    } else if ([method isEqualToString:@"system.swizzle"]) {
        result = FCPBridge_handleSystemSwizzle(params);
    } else if ([method isEqualToString:@"system.getProperties"]) {
        result = FCPBridge_handleSystemGetProperties(params);
    } else if ([method isEqualToString:@"system.getProtocols"]) {
        result = FCPBridge_handleSystemGetProtocols(params);
    } else if ([method isEqualToString:@"system.getSuperchain"]) {
        result = FCPBridge_handleSystemGetSuperchain(params);
    } else if ([method isEqualToString:@"system.getIvars"]) {
        result = FCPBridge_handleSystemGetIvars(params);
    } else {
        return @{@"error": @{@"code": @(-32601), @"message":
                     [NSString stringWithFormat:@"Method not found: %@", method]}};
    }

    if (result[@"error"] && ![result[@"error"] isKindOfClass:[NSDictionary class]]) {
        return @{@"error": @{@"code": @(-32000), @"message": result[@"error"]}};
    }

    return @{@"result": result};
}

#pragma mark - Client Handler

static void FCPBridge_handleClient(int clientFd) {
    FCPBridge_log(@"Client connected (fd=%d)", clientFd);

    dispatch_async(sClientQueue, ^{
        [sConnectedClients addObject:@(clientFd)];
    });

    FILE *stream = fdopen(clientFd, "r+");
    if (!stream) {
        close(clientFd);
        return;
    }

    char buffer[65536];
    while (fgets(buffer, sizeof(buffer), stream)) {
        @autoreleasepool {
            NSData *data = [NSData dataWithBytes:buffer length:strlen(buffer)];
            NSError *jsonError = nil;
            NSDictionary *request = [NSJSONSerialization JSONObjectWithData:data
                                                                   options:0
                                                                     error:&jsonError];

            NSMutableDictionary *response = [NSMutableDictionary dictionary];
            response[@"jsonrpc"] = @"2.0";

            if (request[@"id"]) {
                response[@"id"] = request[@"id"];
            }

            if (jsonError || !request) {
                response[@"error"] = @{@"code": @(-32700),
                                       @"message": @"Parse error"};
            } else {
                @try {
                    NSDictionary *result = FCPBridge_handleRequest(request);
                    if (result[@"error"]) {
                        response[@"error"] = result[@"error"];
                    } else {
                        response[@"result"] = result[@"result"];
                    }
                } @catch (NSException *exception) {
                    FCPBridge_log(@"Exception handling request: %@ - %@",
                                  exception.name, exception.reason);
                    response[@"error"] = @{
                        @"code": @(-32000),
                        @"message": [NSString stringWithFormat:@"Internal error: %@", exception.reason]
                    };
                }
            }

            NSData *responseJson = [NSJSONSerialization dataWithJSONObject:response
                                                                  options:0
                                                                    error:nil];
            if (responseJson) {
                fwrite(responseJson.bytes, 1, responseJson.length, stream);
                fwrite("\n", 1, 1, stream);
                fflush(stream);
            }
        }
    }

    FCPBridge_log(@"Client disconnected (fd=%d)", clientFd);
    dispatch_async(sClientQueue, ^{
        [sConnectedClients removeObject:@(clientFd)];
    });
    fclose(stream);
}

#pragma mark - Server

void FCPBridge_startControlServer(void) {
    sClientQueue = dispatch_queue_create("com.fcpbridge.clients", DISPATCH_QUEUE_SERIAL);
    sConnectedClients = [NSMutableArray array];

    // Use TCP on localhost -- sandbox allows network.server entitlement
    int serverFd = socket(AF_INET, SOCK_STREAM, 0);
    if (serverFd < 0) {
        FCPBridge_log(@"ERROR: Failed to create TCP socket: %s", strerror(errno));
        return;
    }

    // Allow port reuse
    int optval = 1;
    setsockopt(serverFd, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);  // 127.0.0.1 only
    addr.sin_port = htons(FCPBRIDGE_TCP_PORT);

    if (bind(serverFd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        FCPBridge_log(@"ERROR: Failed to bind TCP port %d: %s", FCPBRIDGE_TCP_PORT, strerror(errno));
        close(serverFd);
        return;
    }

    if (listen(serverFd, 5) < 0) {
        FCPBridge_log(@"ERROR: Failed to listen: %s", strerror(errno));
        close(serverFd);
        return;
    }

    FCPBridge_log(@"================================================");
    FCPBridge_log(@"Control server listening on 127.0.0.1:%d", FCPBRIDGE_TCP_PORT);
    FCPBridge_log(@"================================================");

    while (1) {
        int clientFd = accept(serverFd, NULL, NULL);
        if (clientFd < 0) {
            FCPBridge_log(@"Accept error: %s", strerror(errno));
            continue;
        }

        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            FCPBridge_handleClient(clientFd);
        });
    }
}
