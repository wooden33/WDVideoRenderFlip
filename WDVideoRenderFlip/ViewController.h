//
//  ViewController.h
//  VideoDemo
//
//  Created by ByteDance on 2023/11/29.
//

#import <UIKit/UIKit.h>

#define SCREENWIDTH [UIScreen mainScreen].bounds.size.width
#define SCREENHEIGHT [UIScreen mainScreen].bounds.size.height
#define STATUSBARHEIGHT [UIApplication sharedApplication].windows.firstObject.windowScene.statusBarManager.statusBarFrame.size.height

NSString *GMRDTimeMMssStr(double second) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"mm:ss";
    return [formatter stringFromDate:[NSDate dateWithTimeIntervalSinceReferenceDate:second]];
}

const static double kToolBarHeight = 44.f;

@interface ViewController : UIViewController


@end

