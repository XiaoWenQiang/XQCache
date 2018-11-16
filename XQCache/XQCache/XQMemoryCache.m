//
//  XQMemoryCache.m
//  XQCache
//
//  Created by xiaoqiang on 2018/11/14.
//  Copyright © 2018 com. All rights reserved.
//

#import "XQMemoryCache.h"
#import <UIKit/UIKit.h>

static inline dispatch_queue_t XQMemoryCacheGetReleaseQueue() {
    dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
    return queue;
}

@interface XQLinkedMapNode : NSObject {
    @package
    __unsafe_unretained XQLinkedMapNode *_prev;
    __unsafe_unretained XQLinkedMapNode *_next;
    id _key;
    id _value;
    NSUInteger _cost;
    NSTimeInterval _time;
}

@end

@implementation XQLinkedMapNode
@end


@interface XQLinkedMap : NSObject{
    @package
    NSMutableDictionary *_dic;
    NSUInteger _totalCost;
    NSUInteger _totalCount;
    XQLinkedMapNode *_head;
    XQLinkedMapNode *_tail;
    BOOL _releaseOnMainThread;
    BOOL _releaseAsynchronously;
}

- (void)insterNodeAtHead:(XQLinkedMapNode *)node;
- (void)bringNodeToHead:(XQLinkedMapNode *)node;
- (void)removeNode:(XQLinkedMapNode *)node;
- (XQLinkedMapNode *)removeTailNode;
- (void)removeAll;

@end

@implementation XQLinkedMap

- (instancetype)init {
    if (self = [super init]) {
        _dic = [NSMutableDictionary dictionary];
        _releaseOnMainThread = NO;
        _releaseAsynchronously = YES;
    }
    return self;
}

- (void)insterNodeAtHead:(XQLinkedMapNode *)node {
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

- (void)bringNodeToHead:(XQLinkedMapNode *)node {
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

- (void)removeNode:(XQLinkedMapNode *)node {
    [_dic removeObjectForKey:node->_key];
    
    _totalCost -= node->_cost;
    _totalCount--;
    if (node->_next) node->_next->_prev = node->_prev;
    if (node->_prev) node->_prev->_next = node->_next;
    if (_head == node) _head = node->_next;
    if (_tail == node) _tail = node->_prev;
}

- (XQLinkedMapNode *)removeTailNode {
    if (!_tail) return nil;
    XQLinkedMapNode *tail = _tail;
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
            dispatch_queue_t queue = _releaseOnMainThread ? dispatch_get_main_queue() :XQMemoryCacheGetReleaseQueue();
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


@implementation XQMemoryCache {
    dispatch_semaphore_t _semaphore;
    XQLinkedMap *_linkedMap;
    dispatch_queue_t _queue;
}

+ (nonnull instancetype)sharedMemoryCache {
    static dispatch_once_t onceToken;
    static id instace;
    dispatch_once(&onceToken, ^{
        instace = [self new];
    });
    return instace;
}

- (instancetype)init {
    if (self = [super init]) {
        _semaphore = dispatch_semaphore_create(1);
        _linkedMap = [[XQLinkedMap alloc] init];
        _queue = dispatch_queue_create("com.xiaoqiang.cache.memory", DISPATCH_QUEUE_SERIAL);
        _countLimit = NSUIntegerMax;
        _costLimit = NSUIntegerMax;
        _ageLimit = DBL_MAX;
        _autoTrimInterval = 10.0;
        _shouldRemvoeAllObjectsOnMemoryWarning = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_appDidReceiveMemoryWarningNotification) name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        
        [self _trimRecursively];
    }
    return self;
}

- (void)_appDidReceiveMemoryWarningNotification {
    if (self.didReceiveMemoryWarningBlock) {
        self.didReceiveMemoryWarningBlock(self);
    }
    if (self.shouldRemvoeAllObjectsOnMemoryWarning) {
        [self removeAllObjects];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    [_linkedMap removeAll];
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

- (void)setObject:(id)object forKey:(NSString *)key {
    [self setObject:object forKey:key cost:0];
}
- (void)setObject:(id)object forKey:(NSString *)key cost:(NSUInteger)cost {
    if (!key) {
        return;
    }
    if (!object) {
        [self removeObjectForKey:key];
        return;
    }
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    XQLinkedMapNode *node = [_linkedMap->_dic objectForKey:key];
    NSTimeInterval now = CACurrentMediaTime();
    
    if (node) {
        _linkedMap->_totalCost -= node->_cost;
        _linkedMap->_totalCost += cost;
        
        node->_cost = cost;
        node->_time = now;
        node->_value = object;
        [_linkedMap bringNodeToHead:node];
    } else {
        node = [[XQLinkedMapNode alloc] init];
        node->_cost = cost;
        node->_time = now;
        node->_key = key;
        node->_value = object;
        [_linkedMap insterNodeAtHead:node];
    }
    
    if (_linkedMap->_totalCost > _costLimit) {
        dispatch_async(_queue, ^{
            [self trimToCost:self->_costLimit];
        });
    }
    if (_linkedMap->_totalCount > _countLimit) {
        XQLinkedMapNode *node = [_linkedMap removeTailNode];
        if (_linkedMap->_releaseAsynchronously) {
            dispatch_queue_t queue = _linkedMap->_releaseOnMainThread ? dispatch_get_main_queue() : XQMemoryCacheGetReleaseQueue();
            dispatch_async(queue, ^{
                [node class]; //hold and release in queue
            });
        } else if (_linkedMap->_releaseOnMainThread && ![NSThread isMainThread]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [node class]; //hold and release in queue
            });
        }
    }
    dispatch_semaphore_signal(_semaphore);
}


#pragma mark - getCache
- (id)objectForKey:(NSString *)key {
    if (!key) {
        return nil;
    }
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    XQLinkedMapNode *node = [_linkedMap->_dic objectForKey:key];
    if (node) {
        node->_time = CACurrentMediaTime();
        [_linkedMap bringNodeToHead:node];
    }
    dispatch_semaphore_signal(_semaphore);
    return node ? node->_value : nil;
}

#pragma mark - remove
- (void)removeAllObjects {
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    [_linkedMap removeAll];
    dispatch_semaphore_signal(_semaphore);
}
- (void)removeObjectForKey:(NSString *)key {
    if (!key) return;
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    XQLinkedMapNode *node = [_linkedMap->_dic objectForKey:key];
    if (node) {
        [_linkedMap removeNode:node];
        if (_linkedMap->_releaseAsynchronously) {
            dispatch_queue_t queue = _linkedMap->_releaseOnMainThread ? dispatch_get_main_queue() : XQMemoryCacheGetReleaseQueue();
            dispatch_async(queue, ^{
                [node class];
            });
        } else if (_linkedMap->_releaseOnMainThread && ![NSThread isMainThread]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [node class];
            });
        }
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
            XQLinkedMapNode *node = [_linkedMap removeTailNode];
            [holder addObject:node];
        } else {
            isFinish = YES;
        }
        dispatch_semaphore_signal(_semaphore);
    }
    if (holder.count > 0) {
        dispatch_queue_t queue = _linkedMap->_releaseOnMainThread ? dispatch_get_main_queue() : XQMemoryCacheGetReleaseQueue();
        dispatch_async(queue, ^{
            [holder count];
        });
    }
}

- (void)_trimToCost:(NSUInteger)costLimit {
    BOOL isFinish = NO;
    dispatch_semaphore_wait(_semaphore, DISPATCH_TIME_FOREVER);
    if (costLimit == 0) {
        [_linkedMap removeAll];
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
            XQLinkedMapNode *node = [_linkedMap removeTailNode];
            [holder addObject:node];
        } else {
            isFinish = YES;
        }
        dispatch_semaphore_signal(_semaphore);
    }
    if (holder.count > 0) {
        dispatch_queue_t queue = _linkedMap->_releaseOnMainThread ? dispatch_get_main_queue() : XQMemoryCacheGetReleaseQueue();
        dispatch_async(queue, ^{
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
            XQLinkedMapNode *node = [_linkedMap removeTailNode];
            if (node) {
                [holder addObject:node];
            }
        }
        dispatch_semaphore_signal(_semaphore);
    }
    if (holder.count > 0) {
        dispatch_queue_t queue = _linkedMap->_releaseOnMainThread ? dispatch_get_main_queue() : XQMemoryCacheGetReleaseQueue();
        dispatch_async(queue, ^{
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




@end
