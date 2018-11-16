//
//  ViewController.m
//  XQCache
//
//  Created by xiaoqiang on 2018/11/14.
//  Copyright © 2018 com. All rights reserved.
//

#import "ViewController.h"
#import "XQMemoryCache.h"
#import "XQDiskCache.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
//    XQMemoryCache *cache = [XQMemoryCache sharedMemoryCache];
//    cache.name = @"测试";
//    [cache setObject:@"发生大幅度绯闻绯闻绯闻绯闻绯闻" forKey:@"icon_washCar_photo_1"];
//    [cache setObject:[UIImage imageNamed:@"icon_washCar_photo_2"] forKey:@"icon_washCar_photo_2"];
//    [cache setObject:[UIImage imageNamed:@"icon_washCar_photo_3"] forKey:@"icon_washCar_photo_3"];
//    [cache setObject:[UIImage imageNamed:@"icon_washCar_photo_4"] forKey:@"icon_washCar_photo_4"];
//    [cache setObject:[UIImage imageNamed:@"icon_washCar_photo_5"] forKey:@"icon_washCar_photo_5"];
//    [cache setObject:[UIImage imageNamed:@"icon_washCar_photo_6"] forKey:@"icon_washCar_photo_6"];
//
//    sleep(5);
//
    UIImage *image = [[XQMemoryCache sharedMemoryCache] objectForKey:@"icon_washCar_photo_1"];
    NSLog(@"%@",image);

    XQDiskCache *cache = [[XQDiskCache alloc] init];
    NSData *data = UIImagePNGRepresentation([UIImage imageNamed:@"icon_washCar_photo_2"]);
    [cache setObject:data forKey:@"icon_washCar_photo_3"];
    sleep(2);
    NSData *string = [cache objectForKey:@"icon_washCar_photo_3"];
    NSLog(@"%@ ",[UIImage imageWithData:string]);

}



@end
