//
//  TZPhotoPickerController.h
//  TZImagePickerController
//
//  Created by 谭真 on 15/12/24.
//  Copyright © 2015年 谭真. All rights reserved.
//

#import <UIKit/UIKit.h>

@class TZAlbumModel;
@interface TZPhotoPickerController : UIViewController

@property (nonatomic, assign) BOOL isFirstAppear;
@property (nonatomic, assign) NSInteger columnNumber;
@property (nonatomic, strong) TZAlbumModel *model;
///是否需要30M控制  yes 需要  no  不需要
@property (nonatomic, assign) BOOL  isNeedSizeControl;

@property (nonatomic, assign) float  videoMaxDuration;
@end


@interface TZCollectionView : UICollectionView

@end
