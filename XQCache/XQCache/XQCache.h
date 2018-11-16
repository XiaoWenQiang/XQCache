//
//  XQCache.h
//  XQCache
//
//  Created by xiaoqiang on 2018/11/14.
//  Copyright © 2018 com. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger,XQCacheType) {
    XQCacheTypeMemory,
    XQCacheTypeDisk
};

@interface XQCache : NSObject

- (instancetype)initWithPath:(NSString *)path;

- (instancetype)initWithPath:(NSString *)path diskCacheDirectory:(NSString *)directory;

/**
 isContain
 */
- (BOOL)isContainObjectWithKey:(NSString *)key;

- (void)isContainObjectWithKey:(NSString *)key withBlock:(void(^)(BOOL isContain ,NSString *key))block;


/**
 setCache
 */

- (void)setObject:(id<NSCopying>)object forKey:(NSString *)key;
- (void)setObject:(id<NSCopying>)object forKey:(NSString *)key withBlock:(void(^)(BOOL))isSuccess;


/**
 getCache
 */

- (id<NSCopying>)objectForKey:(NSString *)key;
- (void)objectForKey:(NSString *)key withBlock:(void(^)(id<NSCopying> object,NSString *key))block;


/**
 remove
 */
- (void)removeAllObject;

- (BOOL)removeObjectForKey:(NSString *)key;

- (void)removeObjectForKey:(NSString *)key withBlock:(void(^)(BOOL isSuccess,NSString *key))bolck;

@end

NS_ASSUME_NONNULL_END
