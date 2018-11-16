//
//  XQMemoryCache.h
//  XQCache
//
//  Created by xiaoqiang on 2018/11/14.
//  Copyright © 2018 com. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface XQMemoryCache : NSObject

@property (nonatomic,copy) NSString *name;

@property (atomic,readonly) NSUInteger totalCount;

@property (atomic,readonly) NSUInteger totalCost;


/**************************/
@property (nonatomic,assign) NSInteger countLimit;

@property (nonatomic,assign) NSInteger costLimit;

@property (nonatomic,assign) NSInteger ageLimit;

@property (nonatomic,assign) NSTimeInterval autoTrimInterval; //默认 10秒

@property (nonatomic, assign) BOOL shouldRemvoeAllObjectsOnMemoryWarning;

@property (nonatomic, assign) BOOL releaseOnMainThread;

@property (nonatomic, assign) BOOL releaseAsynchronously;

@property (nullable, copy) void(^didReceiveMemoryWarningBlock)(XQMemoryCache *cache);


+ (nonnull instancetype)sharedMemoryCache;


/**
 isContain
 */
- (BOOL)isContainsObjectForKey:(NSString *)key;

/**
 setCache
 */
- (void)setObject:(id)object forKey:(NSString *)key;
- (void)setObject:(id)object forKey:(NSString *)key cost:(NSUInteger)cost;


/**
 getCache
 */
- (id)objectForKey:(NSString *)key;

/**
 remove
 */
- (void)removeAllObjects;
- (void)removeObjectForKey:(NSString *)key;


/**
 删除数据达到某个限制：策略LRU
 */

- (void)trimToCount:(NSUInteger)count;

- (void)trimToCost:(NSUInteger)cost;

- (void)trimToAge:(NSTimeInterval)age;

@end

NS_ASSUME_NONNULL_END
