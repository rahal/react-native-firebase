#import "RNFirebaseFirestoreDocumentReference.h"

@implementation RNFirebaseFirestoreDocumentReference

#if __has_include(<FirebaseFirestore/FirebaseFirestore.h>)

static NSMutableDictionary *_listeners;

- (id)initWithPath:(RCTEventEmitter *)emitter
               app:(NSString *) app
              path:(NSString *) path {
    self = [super init];
    if (self) {
        _emitter = emitter;
        _app = app;
        _path = path;
        _ref = [[RNFirebaseFirestore getFirestoreForApp:_app] documentWithPath:_path];
    }
    // Initialise the static listeners object if required
    if (!_listeners) {
        _listeners = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)collections:(RCTPromiseResolveBlock) resolve
           rejecter:(RCTPromiseRejectBlock) reject {
    // Not supported on iOS
}

- (void)create:(NSDictionary *) data
      resolver:(RCTPromiseResolveBlock) resolve
      rejecter:(RCTPromiseRejectBlock) reject {
    // Not supported on iOS out of the box
}

- (void)delete:(RCTPromiseResolveBlock) resolve
      rejecter:(RCTPromiseRejectBlock) reject {
    [_ref deleteDocumentWithCompletion:^(NSError * _Nullable error) {
        [RNFirebaseFirestoreDocumentReference handleWriteResponse:error resolver:resolve rejecter:reject];
    }];
}

- (void)get:(RCTPromiseResolveBlock) resolve
   rejecter:(RCTPromiseRejectBlock) reject {
    [_ref getDocumentWithCompletion:^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable error) {
        if (error) {
            [RNFirebaseFirestore promiseRejectException:reject error:error];
        } else {
            NSDictionary *data = [RNFirebaseFirestoreDocumentReference snapshotToDictionary:snapshot];
            resolve(data);
        }
    }];
}

+ (void)offSnapshot:(NSString *) listenerId {
    id<FIRListenerRegistration> listener = _listeners[listenerId];
    if (listener) {
        [_listeners removeObjectForKey:listenerId];
        [listener remove];
    }
}

- (void)onSnapshot:(NSString *) listenerId
  docListenOptions:(NSDictionary *) docListenOptions {
    if (_listeners[listenerId] == nil) {
        id listenerBlock = ^(FIRDocumentSnapshot * _Nullable snapshot, NSError * _Nullable error) {
            if (error) {
                id<FIRListenerRegistration> listener = _listeners[listenerId];
                if (listener) {
                    [_listeners removeObjectForKey:listenerId];
                    [listener remove];
                }
                [self handleDocumentSnapshotError:listenerId error:error];
            } else {
                [self handleDocumentSnapshotEvent:listenerId documentSnapshot:snapshot];
            }
        };
        FIRDocumentListenOptions *options = [[FIRDocumentListenOptions alloc] init];
        if (docListenOptions && docListenOptions[@"includeMetadataChanges"]) {
            [options includeMetadataChanges:TRUE];
        }
        id<FIRListenerRegistration> listener = [_ref addSnapshotListenerWithOptions:options listener:listenerBlock];
        _listeners[listenerId] = listener;
    }
}

- (void)set:(NSDictionary *) data
    options:(NSDictionary *) options
   resolver:(RCTPromiseResolveBlock) resolve
   rejecter:(RCTPromiseRejectBlock) reject {
    NSDictionary *dictionary = [RNFirebaseFirestoreDocumentReference parseJSMap:[RNFirebaseFirestore getFirestoreForApp:_app] jsMap:data];
    if (options && options[@"merge"]) {
        [_ref setData:dictionary options:[FIRSetOptions merge] completion:^(NSError * _Nullable error) {
            [RNFirebaseFirestoreDocumentReference handleWriteResponse:error resolver:resolve rejecter:reject];
        }];
    } else {
        [_ref setData:dictionary completion:^(NSError * _Nullable error) {
            [RNFirebaseFirestoreDocumentReference handleWriteResponse:error resolver:resolve rejecter:reject];
        }];
    }
}

- (void)update:(NSDictionary *) data
      resolver:(RCTPromiseResolveBlock) resolve
      rejecter:(RCTPromiseRejectBlock) reject {
    NSDictionary *dictionary = [RNFirebaseFirestoreDocumentReference parseJSMap:[RNFirebaseFirestore getFirestoreForApp:_app] jsMap:data];
    [_ref updateData:dictionary completion:^(NSError * _Nullable error) {
        [RNFirebaseFirestoreDocumentReference handleWriteResponse:error resolver:resolve rejecter:reject];
    }];
}

- (BOOL)hasListeners {
    return [[_listeners allKeys] count] > 0;
}

+ (void)handleWriteResponse:(NSError *) error
                   resolver:(RCTPromiseResolveBlock) resolve
                   rejecter:(RCTPromiseRejectBlock) reject {
    if (error) {
        [RNFirebaseFirestore promiseRejectException:reject error:error];
    } else {
        resolve(nil);
    }
}

+ (NSDictionary *)snapshotToDictionary:(FIRDocumentSnapshot *)documentSnapshot {
    NSMutableDictionary *snapshot = [[NSMutableDictionary alloc] init];
    [snapshot setValue:documentSnapshot.reference.path forKey:@"path"];
    if (documentSnapshot.exists) {
        [snapshot setValue:[RNFirebaseFirestoreDocumentReference buildNativeMap:documentSnapshot.data] forKey:@"data"];
    }
    if (documentSnapshot.metadata) {
        NSMutableDictionary *metadata = [[NSMutableDictionary alloc] init];
        [metadata setValue:@(documentSnapshot.metadata.fromCache) forKey:@"fromCache"];
        [metadata setValue:@(documentSnapshot.metadata.hasPendingWrites) forKey:@"hasPendingWrites"];
        [snapshot setValue:metadata forKey:@"metadata"];
    }
    return snapshot;
}

- (void)handleDocumentSnapshotError:(NSString *)listenerId
                              error:(NSError *)error {
    NSMutableDictionary *event = [[NSMutableDictionary alloc] init];
    [event setValue:_app forKey:@"appName"];
    [event setValue:_path forKey:@"path"];
    [event setValue:listenerId forKey:@"listenerId"];
    [event setValue:[RNFirebaseFirestore getJSError:error] forKey:@"error"];

    [_emitter sendEventWithName:FIRESTORE_DOCUMENT_SYNC_EVENT body:event];
}

- (void)handleDocumentSnapshotEvent:(NSString *)listenerId
                   documentSnapshot:(FIRDocumentSnapshot *)documentSnapshot {
    NSMutableDictionary *event = [[NSMutableDictionary alloc] init];
    [event setValue:_app forKey:@"appName"];
    [event setValue:_path forKey:@"path"];
    [event setValue:listenerId forKey:@"listenerId"];
    [event setValue:[RNFirebaseFirestoreDocumentReference snapshotToDictionary:documentSnapshot] forKey:@"documentSnapshot"];

    [_emitter sendEventWithName:FIRESTORE_DOCUMENT_SYNC_EVENT body:event];
}


+ (NSDictionary *)buildNativeMap:(NSDictionary *)nativeMap {
    NSMutableDictionary *map = [[NSMutableDictionary alloc] init];
    [nativeMap enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        NSDictionary *typeMap = [RNFirebaseFirestoreDocumentReference buildTypeMap:obj];
        map[key] = typeMap;
    }];
    
    return map;
}

+ (NSArray *)buildNativeArray:(NSArray *)nativeArray {
    NSMutableArray *array = [[NSMutableArray alloc] init];
    [nativeArray enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary *typeMap = [RNFirebaseFirestoreDocumentReference buildTypeMap:obj];
        [array addObject:typeMap];
    }];
    
    return array;
}

+ (NSDictionary *)buildTypeMap:(id) value {
    NSMutableDictionary *typeMap = [[NSMutableDictionary alloc] init];
    if (!value) {
        typeMap[@"type"] = @"null";
    } else if ([value isKindOfClass:[NSString class]]) {
        typeMap[@"type"] = @"string";
        typeMap[@"value"] = value;
    } else if ([value isKindOfClass:[NSDictionary class]]) {
        typeMap[@"type"] = @"object";
        typeMap[@"value"] = [RNFirebaseFirestoreDocumentReference buildNativeMap:value];
    } else if ([value isKindOfClass:[NSArray class]]) {
        typeMap[@"type"] = @"array";
        typeMap[@"value"] = [RNFirebaseFirestoreDocumentReference buildNativeArray:value];
    } else if ([value isKindOfClass:[FIRDocumentReference class]]) {
        typeMap[@"type"] = @"reference";
        FIRDocumentReference *ref = (FIRDocumentReference *)value;
        typeMap[@"value"] = [ref path];
    } else if ([value isKindOfClass:[FIRGeoPoint class]]) {
        typeMap[@"type"] = @"geopoint";
        FIRGeoPoint *point = (FIRGeoPoint *)value;
        NSMutableDictionary *geopoint = [[NSMutableDictionary alloc] init];
        geopoint[@"latitude"] = @([point latitude]);
        geopoint[@"longitude"] = @([point longitude]);
        typeMap[@"value"] = geopoint;
    } else if ([value isKindOfClass:[NSDate class]]) {
        typeMap[@"type"] = @"date";
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
        typeMap[@"value"] = [dateFormatter stringFromDate:(NSDate *)value];
    } else if ([value isKindOfClass:[NSNumber class]]) {
        NSNumber *number = (NSNumber *)value;
        if (number == (void*)kCFBooleanFalse || number == (void*)kCFBooleanTrue) {
            typeMap[@"type"] = @"boolean";
        } else {
            typeMap[@"type"] = @"number";
        }
        typeMap[@"value"] = value;
    } else {
        // TODO: Log an error
        typeMap[@"type"] = @"null";
    }
    
    return typeMap;
}

+(NSDictionary *)parseJSMap:(FIRFirestore *) firestore
                      jsMap:(NSDictionary *) jsMap {
    NSMutableDictionary* map = [[NSMutableDictionary alloc] init];
    if (jsMap) {
        [jsMap enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
            map[key] = [RNFirebaseFirestoreDocumentReference parseJSTypeMap:firestore jsTypeMap:obj];
        }];
    }
    return map;
}

+(NSArray *)parseJSArray:(FIRFirestore *) firestore
                 jsArray:(NSArray *) jsArray {
    NSMutableArray* array = [[NSMutableArray alloc] init];
    if (jsArray) {
        [jsArray enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [array addObject:[RNFirebaseFirestoreDocumentReference parseJSTypeMap:firestore jsTypeMap:obj]];
        }];
    }
    return array;
}

+(id)parseJSTypeMap:(FIRFirestore *) firestore
          jsTypeMap:(NSDictionary *) jsTypeMap {
    NSString *type = jsTypeMap[@"type"];
    id value = jsTypeMap[@"value"];
    if ([type isEqualToString:@"array"]) {
        return [RNFirebaseFirestoreDocumentReference parseJSArray:firestore jsArray:value];
    } else if ([type isEqualToString:@"object"]) {
        return [RNFirebaseFirestoreDocumentReference parseJSMap:firestore jsMap:value];
    } else if ([type isEqualToString:@"reference"]) {
        return [firestore documentWithPath:value];
    } else if ([type isEqualToString:@"geopoint"]) {
        NSDictionary* geopoint = (NSDictionary*)value;
        NSNumber *latitude = geopoint[@"latitude"];
        NSNumber *longitude = geopoint[@"longitude"];
        return [[FIRGeoPoint alloc] initWithLatitude:[latitude doubleValue] longitude:[longitude doubleValue]];
    } else if ([type isEqualToString:@"date"]) {
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"];
        return [dateFormatter dateFromString:value];
    } else if ([type isEqualToString:@"boolean"] || [type isEqualToString:@"number"] || [type isEqualToString:@"string"] || [type isEqualToString:@"null"]) {
        return value;
    } else {
        // TODO: Log error
        return nil;
    }
}

#endif

@end
