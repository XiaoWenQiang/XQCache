//
//  XQDiskCache.m
//  XQCache
//
//  Created by xiaoqiang on 2018/11/14.
//  Copyright © 2018 com. All rights reserved.
//

#import "XQDiskCache.h"
#import <UIKit/UIKit.h>
#import <CommonCrypto/CommonDigest.h>

static inline dispatch_queue_t XQDishCacheGetReleaseQueue() {
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
    return queue;
}

static inline NSString *getDefaultDiskCachePath() {
    NSArray *cacheArray = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cachePath = [[cacheArray objectAtIndex:0] stringByAppendingPathComponent:@"xiaoqiangCache"];
    return cachePath;
}

static inline NSString* getlinkMapDiskCachePath() {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory,
                                                         NSUserDomainMask, YES);
    NSString *cachesDirectory = [paths objectAtIndex:0];
    NSString *archiveDirPath = [cachesDirectory stringByAppendingFormat:@"/xiaoqiangLinkMapCache/"];    
    NSError* error;
    if (![[NSFileManager defaultManager] fileExistsAtPath:archiveDirPath]) {
        
        if (![[NSFileManager defaultManager] createDirectoryAtPath:archiveDirPath
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:&error])
        {
            NSLog(@"Create directory tmp/cachedModels directory error: %@", error);
            return nil;
        }
    }
    
    NSString *archivePath = [archiveDirPath stringByAppendingFormat:@"/linkedMap"];
    return archivePath;
}

static inline NSString *cachedFileNameForKey(NSString *string) {
    if (!string) return nil;
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(data.bytes, (CC_LONG)data.length, result);
    return [NSString stringWithFormat:
            @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
            result[0],  result[1],  result[2],  result[3],
            result[4],  result[5],  result[6],  result[7],
            result[8],  result[9],  result[10], result[11],
            result[12], result[13], result[14], result[15]
            ];
}

@interface XQLinkedPathMapNode : NSObject<NSCoding,NSCopying>
{
    @package
    __unsafe_unretained XQLinkedPathMapNode *_prev;
    __unsafe_unretained XQLinkedPathMapNode *_next;
    id _key;
    id _valuePath;
    NSUInteger _cost;
    NSTimeInterval _time;
}

@end

@implementation XQLinkedPathMapNode

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_prev forKey:@"_prev"];
    [aCoder encodeObject:_next forKey:@"_next"];
    [aCoder encodeObject:_key forKey:@"_key"];
    [aCoder encodeObject:_valuePath forKey:@"_valuePath"];
    [aCoder encodeObject:@(_cost) forKey:@"_cost"];
    [aCoder encodeObject:@(_time) forKey:@"_time"];
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super init]) {
        _prev = [aDecoder decodeObjectForKey:@"_prev"];
        _next = [aDecoder decodeObjectForKey:@"_next"];
        _key = [aDecoder decodeObjectForKey:@"_key"];
        _valuePath = [aDecoder decodeObjectForKey:@"_valuePath"];
        _cost = [[aDecoder decodeObjectForKey:@"_cost"] integerValue];
        _time = [[aDecoder decodeObjectForKey:@"_time"] integerValue];
    }
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone {
    XQLinkedPathMapNode *newNode = [[XQLinkedPathMapNode allocWithZone:zone] init];
    newNode->_prev = self->_prev;
    newNode->_next = self->_next;
    newNode->_key = self->_key;
    newNode->_valuePath = self->_valuePath;
    newNode->_cost = self->_cost;
    newNode->_time = self->_time;
    return newNode;
}


@end

@interface XQLinkedPathMap : NSObject <NSCoding,NSCopying>
{
    @package
    NSMutableDictionary *_dic;
    NSUInteger _totalCost;
    NSUInteger _totalCount;
    XQLinkedPathMapNode *_head;
    XQLinkedPathMapNode *_tail;
    BOOL _releaseOnMainThread;
    BOOL _releaseAsynchronously;
}

- (void)insterNodeAtHead:(XQLinkedPathMapNode *)node;
- (void)bringNodeToHead:(XQLinkedPathMapNode *)node;
- (void)removeNode:(XQLinkedPathMapNode *)node;
- (XQLinkedPathMapNode *)removeTailNode;
- (void)removeAll;

@end

@implementation XQLinkedPathMap

- (void)encodeWithCoder:(NSCoder *)aCoder {
    [aCoder encodeObject:_dic forKey:@"_dic"];
    [aCoder encodeObject:_head forKey:@"_head"];
    [aCoder encodeObject:_tail forKey:@"_tail"];
    [aCoder encodeObject:@(_releaseOnMainThread) forKey:@"_releaseOnMainThread"];
    [aCoder encodeObject:@(_releaseAsynchronously) forKey:@"_releaseAsynchronously"];
    [aCoder encodeObject:@(_totalCost) forKey:@"_totalCost"];
    [aCoder encodeObject:@(_totalCount) forKey:@"_totalCount"];
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    if (self = [super init]) {
        _dic = [aDecoder decodeObjectForKey:@"_dic"];
        _head = [aDecoder decodeObjectForKey:@"_head"];
        _tail = [aDecoder decodeObjectForKey:@"_tail"];
        _releaseOnMainThread = [[aDecoder decodeObjectForKey:@"_releaseOnMainThread"] boolValue];
        _releaseAsynchronously = [[aDecoder decodeObjectForKey:@"_releaseAsynchronously"] boolValue];
        _totalCost = [[aDecoder decodeObjectForKey:@"_totalCost"] integerValue];
        _totalCount = [[aDecoder decodeObjectForKey:@"_totalCount"] integerValue];
    }
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone {
    XQLinkedPathMap *newNode = [[XQLinkedPathMap allocWithZone:zone] init];
    newNode->_dic = self->_dic;
    newNode->_head = self->_head;
    newNode->_tail = self->_tail;
    newNode->_releaseOnMainThread = self->_releaseOnMainThread;
    newNode->_releaseAsynchronously = self->_releaseAsynchronously;
    newNode->_totalCost = self->_totalCost;
    newNode->_totalCount = self->_totalCount;
    return newNode;
}

- (instancetype)init {
    if (self = [super init]) {
        _dic = [NSMutableDictionary dictionary];
        _releaseOnMainThread = NO;
        _releaseAsynchronously = YES;
    }
    return self;
}

- (void)insterNodeAtHead:(XQLinkedPathMapNode *)node {
    [_dic setObject:node forKey:node->_key];
    _totalCost += node->_cost;
    _totalCount++;
    if (_head) {
        node->_next = _head;
        _head->_prev = node;
        _head = node;
    } else {
        _head = _tail = node;
    }
}

- (void)bringNodeToHead:(XQLinkedPathMapNode *)node {
    if (_head == node) return;
    
    if (_tail == node) {
        _tail = node->_prev;
        _tail->_next = nil;
    } else {
        node->_next->_prev = node->_prev;
        node->_prev->_next = node->_next;
    }
    node->_next = _head;
    node->_prev = nil;
    _head->_prev = node;
    _head = node;
}

- (void)removeNode:(XQLinkedPathMapNode *)node {
    [_dic removeObjectForKey:node->_key];
    
    _totalCost -= node->_cost;
    _totalCount--;
    if (node->_next) node->_next->_prev = node->_prev;
    if (node->_prev) node->_prev->_next = node->_next;
    if (_head == node) _head = node->_next;
    if (_tail == node) _tail = node->_prev;
}

- (XQLinkedPathMapNode *)removeTailNode {
    if (!_tail) return nil;
    XQLinkedPathMapNode *tail = _tail;
    [_dic removeObjectForKey:_tail->_key];
    
    _totalCost -= _tail->_cost;
    _totalCount--;
    if (_head == _tail) {
        _head = _tail = nil;
    } else {
        _tail = _tail->_prev;
        _tail->_next = nil;
    }
    return tail;
}

- (void)removeAll {
    _totalCost = 0;
    _totalCost = 0;
    _head = nil;
    _tail = nil;
    
    if (_dic.allKeys.count > 0) {
        NSMutableDictionary *holder = _dic;
        _dic = [NSMutableDictionary dictionary];
        if (_releaseAsynchronously) {
            dispatch_queue_t queue = _releaseOnMainThread ? dispatch_get_main_queue() :XQDishCacheGetReleaseQueue();
            dispatch_async(queue, ^{
                [holder class];
            });
        } else if (_releaseOnMainThread && ![NSThread isMainThread]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [holder class];
            });
        } else {
            [holder class];
        }
    }
}


@end

@implementation XQDiskCache {
    dispatch_semaphore_t _semaphore;
    XQLinkedPathMap *_linkedMap;
    dispatch_queue_t _queue;
    NSFileManager *_fileManager;
}

- (instancetype)init {
    return [self initWithPath:@"defaultCache"];
}

- (instancetype)initWithPath:(NSString *)path {
    if (self = [super init]) {
        _semaphore = dispatch_semaphore_create(1);
        _queue = dispatch_queue_create("com.xiaoqiang.cache.disk", DISPATCH_QUEUE_SERIAL);
        _countLimit = NSUIntegerMax;
        _costLimit = NSUIntegerMax;
        _ageLimit = DBL_MAX;
        _autoTrimInterval = 10.0;
        _fileManager = [NSFileManager new];
        _path = [getDefaultDiskCachePath() stringByAppendingPathComponent:path];
        if (![_fileManager fileExistsAtPath:_path]) {
            [_fileManager createDirectoryAtPath:_path withIntermediateDirectories:YES attributes:nil error:nil];
        }
        _linkedMap = (XQLinkedPathMap *)[self cachedModelWithIdRemoveWhenUpate:@"ceshi"];
        if (_linkedMap == nil) {
            _linkedMap = [[XQLinkedPathMap alloc] init];
        }
        [self _trimRecursively];
    }
    return self;
}

#pragma mark - isContain
- (BOOL)isContainsObjectForKey:(NSString *)key {
    if (!key) {
        return NO;
    }
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    BOOL isContain = [_linkedMap->_dic objectForKey:key];
    dispatch_semaphore_signal(_semaphore);
    return isContain;
}


#pragma mark - setCache

- (void)setObject:(NSData *)object forKey:(NSString *)key {
    [self setObject:object forKey:key cost:0];
}
- (void)setObject:(NSData *)object forKey:(NSString *)key cost:(NSUInteger)cost {
    if (!key) {
        return;
    }
    if (!object) {
        [self removeObjectForKey:key];
        return;
    }
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    XQLinkedPathMapNode *node = [_linkedMap->_dic objectForKey:key];
    NSTimeInterval now = CACurrentMediaTime();
    
    NSString *cachePathForKey = [self defaultCachePathForKey:key];
    if (node) {
        _linkedMap->_totalCost -= node->_cost;
        _linkedMap->_totalCost += cost;
        
        node->_cost = cost;
        node->_time = now;
        node->_valuePath = cachePathForKey;
        [_linkedMap bringNodeToHead:node];
    } else {
        node = [[XQLinkedPathMapNode alloc] init];
        node->_cost = cost;
        node->_time = now;
        node->_key = key;
        node->_valuePath = cachePathForKey;
        [_linkedMap insterNodeAtHead:node];
    }
    if (_linkedMap->_totalCount > _countLimit) {
        XQLinkedPathMapNode *node = [_linkedMap removeTailNode];
        if (_linkedMap->_releaseAsynchronously) {
            dispatch_queue_t queue = _linkedMap->_releaseOnMainThread ? dispatch_get_main_queue() : XQDishCacheGetReleaseQueue();
            dispatch_async(queue, ^{
                [node class]; //hold and release in queue
            });
        } else if (_linkedMap->_releaseOnMainThread && ![NSThread isMainThread]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [node class]; //hold and release in queue
            });
        }
    }
    
    BOOL isSuccess = [object writeToFile:cachePathForKey atomically:YES];
    if (isSuccess) {
        [self persistCacheModel:[NSArray arrayWithObjects:@"123",@"456",@"789", nil] withId:@"ceshi"];
    }
    dispatch_semaphore_signal(_semaphore);
}


#pragma mark - getCache
- (id)objectForKey:(NSString *)key {
    if (!key) {
        return nil;
    }
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    XQLinkedPathMapNode *node = [_linkedMap->_dic objectForKey:key];
    NSString *cachePathForKey = @"";
    if (node) {
        node->_time = CACurrentMediaTime();
        [_linkedMap bringNodeToHead:node];
        cachePathForKey = node->_valuePath;
    }
    NSData *dataForCache = [NSData dataWithContentsOfFile:cachePathForKey];
    [self persistCacheModel:_linkedMap withId:@"ceshi"];
    dispatch_semaphore_signal(_semaphore);
    return dataForCache ? dataForCache : nil;
}

#pragma mark - remove
- (void)removeAllObjects {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    [_linkedMap removeAll];
    if ([_fileManager fileExistsAtPath:getDefaultDiskCachePath()]) {
        [_fileManager removeItemAtPath:getDefaultDiskCachePath() error:nil];
    }
    [self removeModelWithId];
    dispatch_semaphore_signal(_semaphore);
}
- (void)removeObjectForKey:(NSString *)key {
    if (!key) return;
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    XQLinkedPathMapNode *node = [_linkedMap->_dic objectForKey:key];
    if (node) {
        [_linkedMap removeNode:node];
         NSString *cachePathForKey = [self defaultCachePathForKey:key];
        if ([_fileManager fileExistsAtPath:cachePathForKey.stringByDeletingPathExtension]) {
            [_fileManager removeItemAtPath:cachePathForKey error:nil];
        }
        
        if (_linkedMap->_releaseAsynchronously) {
            dispatch_queue_t queue = _linkedMap->_releaseOnMainThread ? dispatch_get_main_queue() : XQDishCacheGetReleaseQueue();
            dispatch_async(queue, ^{
                [node class];
            });
        } else if (_linkedMap->_releaseOnMainThread && ![NSThread isMainThread]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [node class];
            });
        }
        if (_linkedMap->_totalCost > _costLimit) {
            dispatch_async(_queue, ^{
                [self trimToCost:self->_costLimit];
            });
        }
        if (_linkedMap->_totalCount > _countLimit) {
            XQLinkedPathMapNode *node = [_linkedMap removeTailNode];
            if (_linkedMap->_releaseAsynchronously) {
                dispatch_queue_t queue = _linkedMap->_releaseOnMainThread ? dispatch_get_main_queue() : XQDishCacheGetReleaseQueue();
                dispatch_async(queue, ^{
                    [node class]; //hold and release in queue
                });
            } else if (_linkedMap->_releaseOnMainThread && ![NSThread isMainThread]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [node class]; //hold and release in queue
                });
            }
        }
        [self persistCacheModel:_linkedMap withId:@"ceshi"];
    }
    dispatch_semaphore_signal(_semaphore);
}


#pragma mark -  删除数据达到某个限制：策略LRU

- (void)trimToCount:(NSUInteger)count {
    if (count == 0) {
        [self removeAllObjects];
        return;
    }
    [self _trimToCount:count];
}

- (void)trimToCost:(NSUInteger)cost {
    [self _trimToCost:cost];
}

- (void)trimToAge:(NSTimeInterval)age {
    [self _trimToAge:age];
}

- (void)_trimRecursively {
    __weak typeof (self) _self = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(_autoTrimInterval * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        __strong typeof (_self) self = _self;
        
        [self _trimRecursively];
        [self _trimInBackground];
    });
}

- (void)_trimInBackground {
    dispatch_async(_queue, ^{
        [self _trimToCost:self->_costLimit];
        [self _trimToCount:self->_countLimit];
        [self _trimToAge:self->_ageLimit];
    });
}

- (void)_trimToCount:(NSUInteger)countLimit {
    BOOL isFinish = NO;
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    if (countLimit == 0) {
        [_linkedMap removeAll];
        if ([_fileManager fileExistsAtPath:getDefaultDiskCachePath().stringByDeletingPathExtension]) {
            [_fileManager removeItemAtPath:getDefaultDiskCachePath() error:nil];
        }
        isFinish = YES;
    } else if (_linkedMap->_totalCount < countLimit) {
        isFinish = YES;
    }
    dispatch_semaphore_signal(_semaphore);
    if (isFinish) {
        return;
    }
    NSMutableArray *holder = [NSMutableArray array];
    while (!isFinish) {
        dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
        if (_linkedMap->_totalCount > countLimit) {
            XQLinkedPathMapNode *node = [_linkedMap removeTailNode];
            [holder addObject:node];
        } else {
            isFinish = YES;
        }
        dispatch_semaphore_signal(_semaphore);
    }
    if (holder.count > 0) {
        dispatch_queue_t queue = _linkedMap->_releaseOnMainThread ? dispatch_get_main_queue() : XQDishCacheGetReleaseQueue();
        dispatch_async(queue, ^{
            for (int i = 0; i < holder.count; i ++) {
                XQLinkedPathMapNode *holderNode = [holder objectAtIndex:i];
                NSString *cachePathForKey = [self defaultCachePathForKey:holderNode->_key];
                if ([self->_fileManager fileExistsAtPath:cachePathForKey.stringByDeletingPathExtension]) {
                    [self->_fileManager removeItemAtPath:cachePathForKey error:nil];
                }
            }
            [holder count];
        });
    }
}

- (void)_trimToCost:(NSUInteger)costLimit {
    BOOL isFinish = NO;
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    if (costLimit == 0) {
        [_linkedMap removeAll];
        if ([_fileManager fileExistsAtPath:getDefaultDiskCachePath().stringByDeletingPathExtension]) {
            [_fileManager removeItemAtPath:getDefaultDiskCachePath() error:nil];
        }
        isFinish = YES;
    } else if (_linkedMap->_totalCost < costLimit) {
        isFinish = YES;
    }
    dispatch_semaphore_signal(_semaphore);
    if (isFinish) {
        return;
    }
    NSMutableArray *holder = [NSMutableArray array];
    while (!isFinish) {
        dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
        if (_linkedMap->_totalCost > costLimit) {
            XQLinkedPathMapNode *node = [_linkedMap removeTailNode];
            [holder addObject:node];
        } else {
            isFinish = YES;
        }
        dispatch_semaphore_signal(_semaphore);
    }
    if (holder.count > 0) {
        dispatch_queue_t queue = _linkedMap->_releaseOnMainThread ? dispatch_get_main_queue() : XQDishCacheGetReleaseQueue();
        dispatch_async(queue, ^{
            for (int i = 0; i < holder.count; i ++) {
                XQLinkedPathMapNode *holderNode = [holder objectAtIndex:i];
                NSString *cachePathForKey = [self defaultCachePathForKey:holderNode->_key];
                if ([self->_fileManager fileExistsAtPath:cachePathForKey.stringByDeletingPathExtension]) {
                    [self->_fileManager removeItemAtPath:cachePathForKey error:nil];
                }
            }
            [holder count];
        });
    }
}

- (void)_trimToAge:(NSUInteger)ageLimit {
    BOOL isFinish = NO;
    NSTimeInterval now = CACurrentMediaTime();
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    if (ageLimit <= 0) {
        [_linkedMap removeAll];
        if ([_fileManager fileExistsAtPath:getDefaultDiskCachePath().stringByDeletingPathExtension]) {
            [_fileManager removeItemAtPath:getDefaultDiskCachePath() error:nil];
        }
        isFinish = YES;
    } else if (!_linkedMap->_tail || now - _linkedMap->_tail->_time <= ageLimit) {
        isFinish = YES;
    }
    dispatch_semaphore_signal(_semaphore);
    if (isFinish) {
        return;
    }
    NSMutableArray *holder = [NSMutableArray array];
    while (!isFinish) {
        dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
        if (_linkedMap->_tail && now - _linkedMap->_tail->_time > ageLimit) {
            XQLinkedPathMapNode *node = [_linkedMap removeTailNode];
            if (node) {
                [holder addObject:node];
            }
        }
        dispatch_semaphore_signal(_semaphore);
    }
    if (holder.count > 0) {
        dispatch_queue_t queue = _linkedMap->_releaseOnMainThread ? dispatch_get_main_queue() : XQDishCacheGetReleaseQueue();
        dispatch_async(queue, ^{
            for (int i = 0; i < holder.count; i ++) {
                XQLinkedPathMapNode *holderNode = [holder objectAtIndex:i];
                NSString *cachePathForKey = [self defaultCachePathForKey:holderNode->_key];
                if ([self->_fileManager fileExistsAtPath:cachePathForKey.stringByDeletingPathExtension]) {
                    [self->_fileManager removeItemAtPath:cachePathForKey error:nil];
                }
            }
            [holder count];
        });
    }
    
}

- (NSUInteger)totalCount {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    NSUInteger count = _linkedMap->_totalCount;
    dispatch_semaphore_signal(_semaphore);
    return count;
}

- (NSUInteger)totalCost {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    NSUInteger totalCost = _linkedMap->_totalCost;
    dispatch_semaphore_signal(_semaphore);
    return totalCost;
}

- (BOOL)releaseOnMainThread {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    BOOL releaseOnMainThread = _linkedMap->_releaseOnMainThread;
    dispatch_semaphore_signal(_semaphore);
    return releaseOnMainThread;
}

- (void)setReleaseOnMainThread:(BOOL)releaseOnMainThread {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    _linkedMap->_releaseOnMainThread = releaseOnMainThread;
    dispatch_semaphore_signal(_semaphore);
}

- (BOOL)releaseAsynchronously {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    BOOL releaseAsynchronously = _linkedMap->_releaseAsynchronously;
    dispatch_semaphore_signal(_semaphore);
    return releaseAsynchronously;
}

- (void)setReleaseAsynchronously:(BOOL)releaseAsynchronously {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    _linkedMap->_releaseAsynchronously = releaseAsynchronously;
    dispatch_semaphore_signal(_semaphore);
}

- (nullable NSString *)cachePathForKey:(nullable NSString *)key inPath:(nonnull NSString *)path {
    NSString *filename = cachedFileNameForKey(key);
    return [path stringByAppendingPathComponent:filename];
}

- (nullable NSString *)defaultCachePathForKey:(nullable NSString *)key {
    return [self cachePathForKey:key inPath:self.path];
}

- (BOOL)persistCacheModel:(id<NSCoding>)model withId:(NSString*)modelId {//写入
    if (modelId)
        return [NSKeyedArchiver archiveRootObject:model toFile:getlinkMapDiskCachePath()];
    else
        return NO;
}

- (id<NSCoding>)cachedModelWithIdRemoveWhenUpate:(NSString*)modelId {//读取
    if (modelId)
        return [NSKeyedUnarchiver unarchiveObjectWithFile:getlinkMapDiskCachePath()];
    else
        return nil;
}

- (void)removeModelWithId {//读取
    NSError *error = nil;
    if (getlinkMapDiskCachePath()) {
        [[NSFileManager defaultManager] removeItemAtPath:getlinkMapDiskCachePath() error:&error];
        if (error) {
            NSLog(@"移除文件失败，错误信息：%@", error);
        }
        else {
            NSLog(@"成功移除文件");
        }
    }
    else {
        NSLog(@"文件不存在");
    }
}

@end
