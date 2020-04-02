//
//  CCMain.m
//  Nextcloud
//
//  Created by Marino Faggiana on 04/09/14.
//  Copyright (c) 2017 Marino Faggiana. All rights reserved.
//
//  Author Marino Faggiana <marino.faggiana@nextcloud.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#import "CCMain.h"
#import "AppDelegate.h"
#import "CCSynchronize.h"
#import "OCActivity.h"
#import "OCNotifications.h"
#import "OCNotificationsAction.h"
#import "OCFrameworkConstants.h"
#import "OCCapabilities.h"
#import "NCAutoUpload.h"
#import "NCBridgeSwift.h"
#import "NCNetworkingEndToEnd.h"
#import "PKDownloadButton.h"

@interface CCMain () <UITextViewDelegate, createFormUploadAssetsDelegate, MGSwipeTableCellDelegate, NCSelectDelegate, UITextFieldDelegate, UIAdaptivePresentationControllerDelegate, NCCreateFormUploadConflictDelegate>
{
    AppDelegate *appDelegate;
        
    BOOL _isRoot;
    BOOL _isViewDidLoad;
    
    NSMutableDictionary *_selectedocIdsMetadatas;
    NSUInteger _numSelectedocIdsMetadatas;
    
    UIImageView *_imageTitleHome;
    
    NSUInteger _failedAttempts;
    NSDate *_lockUntilDate;

    NCMainRefreshControl *refreshControl;

    CCHud *_hud;
    
    // Datasource
    CCSectionDataSourceMetadata *sectionDataSource;
    NSDate *_dateReadDataSource;
    
    // Search
    NSString *_searchFileName;
    NSMutableArray *_searchResultMetadatas;
    NSString *_noFilesSearchTitle;
    NSString *_noFilesSearchDescription;
    NSTimer *_timerWaitInput;

    // Automatic Upload Folder
    NSString *_autoUploadFileName;
    NSString *_autoUploadDirectory;
    
    // Folder
    BOOL _loadingFolder;
    tableMetadata *_metadataFolder;
    
    CGFloat heightRichWorkspace;
    CGFloat heightSearchBar;
}
@end

@implementation CCMain

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Init =====
#pragma --------------------------------------------------------------------------------------------

-  (id)initWithCoder:(NSCoder *)aDecoder
{    
    if (self = [super initWithCoder:aDecoder])  {
        
        appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
        appDelegate.activeMain = self;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(initializeMain:) name:k_notificationCenter_initializeMain object:nil];
    }
    
    return self;
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== View =====
#pragma --------------------------------------------------------------------------------------------

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // init object
    self.metadata = [tableMetadata new];
    _hud = [[CCHud alloc] initWithView:[[[UIApplication sharedApplication] delegate] window]];
    _selectedocIdsMetadatas = [NSMutableDictionary new];
    _isViewDidLoad = YES;
    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchResultMetadatas = [NSMutableArray new];
    _searchFileName = @"";
    _noFilesSearchTitle = @"";
    _noFilesSearchDescription = @"";
    _cellFavouriteImage = [CCGraphics changeThemingColorImage:[UIImage imageNamed:@"favorite"] width:50 height:50 color:[UIColor whiteColor]];
    _cellTrashImage = [CCGraphics changeThemingColorImage:[UIImage imageNamed:@"trash"] width:50 height:50 color:[UIColor whiteColor]];
    
    // delegate
    self.tableView.delegate = self;
    self.tableView.tableFooterView = [UIView new];
    self.tableView.emptyDataSetDelegate = self;
    self.tableView.emptyDataSetSource = self;
    self.searchController.delegate = self;
    self.searchController.searchBar.delegate = self;
    
    // Notification
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clearDateReadDataSource:) name:k_notificationCenter_clearDateReadDataSource object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(setTitle) name:k_notificationCenter_setTitleMain object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(triggerProgressTask:) name:k_notificationCenter_progressTask object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(deleteFile:) name:k_notificationCenter_deleteFile object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(favoriteFile:) name:k_notificationCenter_favoriteFile object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(renameFile:) name:k_notificationCenter_renameFile object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(createFolder:) name:k_notificationCenter_createFolder object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(changeTheming) name:k_notificationCenter_changeTheming object:nil];
    
    // Search
    self.definesPresentationContext = YES;
    self.searchController.searchResultsUpdater = self;
    self.searchController.dimsBackgroundDuringPresentation = NO;
    self.searchController.searchBar.translucent = NO;
    [self.searchController.searchBar sizeToFit];
    self.searchController.searchBar.delegate = self;
    self.searchController.searchBar.barTintColor = NCBrandColor.sharedInstance.brand;
    self.searchController.searchBar.backgroundColor = NCBrandColor.sharedInstance.brand;
    self.searchController.searchBar.backgroundImage = [UIImage new];
    UIButton *searchButton = self.searchController.searchBar.subviews.firstObject.subviews.lastObject;
    if (searchButton && [searchButton isKindOfClass:[UIButton class]]) {
        [searchButton setTitleColor:NCBrandColor.sharedInstance.brandText forState:UIControlStateNormal];
    }
    UITextField *searchTextView = [self.searchController.searchBar valueForKey:@"searchField"];
    if (searchTextView && [searchTextView isKindOfClass:[UITextField class]]) {
        searchTextView.backgroundColor = NCBrandColor.sharedInstance.backgroundForm;
        searchTextView.textColor = NCBrandColor.sharedInstance.textView;
    }
    heightSearchBar = self.searchController.searchBar.frame.size.height;
    
    // Load Rich Workspace
    self.viewRichWorkspace = [[[NSBundle mainBundle] loadNibNamed:@"NCRichWorkspace" owner:self options:nil] firstObject];
    if (@available(iOS 11, *)) {
        UITapGestureRecognizer *viewRichWorkspaceTapped = [[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(viewRichWorkspaceTapAction:)];
        viewRichWorkspaceTapped.numberOfTapsRequired = 1;
        viewRichWorkspaceTapped.delegate = self;
        [self.viewRichWorkspace addGestureRecognizer:viewRichWorkspaceTapped];
    }
    heightRichWorkspace = UIScreen.mainScreen.bounds.size.height/4 + heightSearchBar;
    self.viewRichWorkspace.textViewTopConstraint.constant = heightSearchBar;
    [self.viewRichWorkspace setFrame:CGRectMake(0, 0, self.tableView.frame.size.width, heightRichWorkspace)];
    
    // Table Header View
    [self.tableView setTableHeaderView:self.viewRichWorkspace];
    [self.tableView.tableHeaderView addSubview:self.searchController.searchBar];
    
    // Register cell
    [self.tableView registerNib:[UINib nibWithNibName:@"CCCellMain" bundle:nil] forCellReuseIdentifier:@"CellMain"];
    [self.tableView registerNib:[UINib nibWithNibName:@"CCCellMainTransfer" bundle:nil] forCellReuseIdentifier:@"CellMainTransfer"];
    
    // long press recognizer TableView
    UILongPressGestureRecognizer* longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(onLongPressTableView:)];
    [self.tableView addGestureRecognizer:longPressRecognizer];
    
    // Pull-to-Refresh
    [self createRefreshControl];
    
    // Register for 3D Touch Previewing if available
    if ([self.traitCollection respondsToSelector:@selector(forceTouchCapability)] && (self.traitCollection.forceTouchCapability == UIForceTouchCapabilityAvailable)) {
        [self registerForPreviewingWithDelegate:self sourceView:self.view];
    }

    // if this is not Main (the Main uses inizializeMain)
    if (_isRoot == NO && appDelegate.activeAccount.length > 0) {
        // Read (File) Folder
        [self readFileReloadFolder];
    }
    
    // Title
    [self setTitle];

    // changeTheming
    [self changeTheming];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    // test
    if (appDelegate.activeAccount.length == 0)
        return;
    
    if (_isSelectedMode)
        [self setUINavigationBarSelected];
    else
        [self setUINavigationBarDefault];
    
    // If not editing mode remove _selectedocIds
    if (!self.tableView.editing)
        [_selectedocIdsMetadatas removeAllObjects];

    // Check server URL "/"
    if (self.navigationController.viewControllers.firstObject == self && self.serverUrl == nil) {
        self.serverUrl = [CCUtility getHomeServerUrlActiveUrl:appDelegate.activeUrl];
    }
    
    // Query data source
    if (self.searchController.isActive == false) {
        [self queryDatasourceWithReloadData:YES serverUrl:self.serverUrl];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    // Active Main
    appDelegate.activeMain = self;
    
    // Test viewDidLoad
    if (_isViewDidLoad) {
        
        _isViewDidLoad = NO;
        
    } else {
        
        if (appDelegate.activeAccount.length > 0 && [_selectedocIdsMetadatas count] == 0) {
            // Read (file) Folder
            [self readFileReloadFolder];
        }
    }

    if (appDelegate.activeAccount.length > 0 && self.serverUrl != nil) {
        
        // Get Shares
        appDelegate.shares = [[NCManageDatabase sharedInstance] getTableSharesWithAccount:appDelegate.activeAccount serverUrl:self.serverUrl];
        
        // Get RichWorkspace
        tableDirectory *directory = [[NCManageDatabase sharedInstance] getTableDirectoryWithPredicate:[NSPredicate predicateWithFormat:@"account == %@ AND serverUrl == %@", appDelegate.activeAccount, self.serverUrl]];
        self.richWorkspaceText = directory.richWorkspace;
    }
    
    // Title
    [self setTitle];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
}

- (void) viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    [self setTableViewHeader];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        
        if (self.view.frame.size.width == ([[UIScreen mainScreen] bounds].size.width*([[UIScreen mainScreen] bounds].size.width<[[UIScreen mainScreen] bounds].size.height))+([[UIScreen mainScreen] bounds].size.height*([[UIScreen mainScreen] bounds].size.width>[[UIScreen mainScreen] bounds].size.height))) {
            
            // Portrait
            
        } else {
            
            // Landscape
        }
        
        [self setTableViewHeader];
    }];
}

- (void)presentationControllerWillDismiss:(UIPresentationController *)presentationController
{
    [self viewDidAppear:true];
}

- (BOOL)prefersStatusBarHidden
{
    return NO;
}

// detect scroll for remove keyboard in search mode
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    if (self.searchController.isActive && scrollView == self.tableView) {
        
        [self.searchController.searchBar endEditing:YES];
    }
}

- (void)changeTheming
{
    [appDelegate changeTheming:self tableView:self.tableView collectionView:nil form:false];
    
    // createImagesThemingColor
    [[NCMainCommon sharedInstance] createImagesThemingColor];
    
    // Refresh control
    refreshControl.tintColor = NCBrandColor.sharedInstance.brandText;
    refreshControl.backgroundColor = NCBrandColor.sharedInstance.brand;

    // color searchbar
    self.searchController.searchBar.barTintColor = NCBrandColor.sharedInstance.brand;
    self.searchController.searchBar.backgroundColor = NCBrandColor.sharedInstance.brand;
    // color searchbbar button text (cancel)
    UIButton *searchButton = self.searchController.searchBar.subviews.firstObject.subviews.lastObject;
    if (searchButton && [searchButton isKindOfClass:[UIButton class]]) {
        [searchButton setTitleColor:NCBrandColor.sharedInstance.brandText forState:UIControlStateNormal];
    }
    // color textview searchbbar
    UITextField *searchTextView = [self.searchController.searchBar valueForKey:@"searchField"];
    if (searchTextView && [searchTextView isKindOfClass:[UITextField class]]) {
        searchTextView.backgroundColor = NCBrandColor.sharedInstance.backgroundForm;
        searchTextView.textColor = NCBrandColor.sharedInstance.textView;
    }
    
    // Rich Workspace
    [self.viewRichWorkspace loadWithRichWorkspaceText:self.richWorkspaceText];
    
    // Title
    [self setTitle];
    
    // Reload Table View
    [self tableViewReloadData];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Initialization =====
#pragma --------------------------------------------------------------------------------------------

//
// Callers :
//
// ChangeDefaultAccount (delegate)
// Split : inizialize
// Settings Advanced : removeAllFiles
//
- (void)initializeMain:(NSNotification *)notification
{
    _dateReadDataSource = nil;
    
    // test
    if (appDelegate.activeAccount.length == 0)
        return;
    
    if ([appDelegate.listMainVC count] == 0 || _isRoot) {
        
        // This is Root home main add list
        appDelegate.homeMain = self;
        _isRoot = YES;
        _serverUrl = [CCUtility getHomeServerUrlActiveUrl:appDelegate.activeUrl];
        [appDelegate.listMainVC setObject:self forKey:_serverUrl];
        
        // go Home
        [self.navigationController popToRootViewControllerAnimated:NO];
                
        // Remove search mode
        [self cancelSearchBar];
        
        // Clear error certificate
        [CCUtility setCertificateError:appDelegate.activeAccount error:NO];
        
        // Setting Theming
        [appDelegate settingThemingColorBrand];
        
        // Detail
        // If AVPlayer in play -> Stop
        if (appDelegate.player != nil && appDelegate.player.rate != 0) {
            [appDelegate.player pause];
        }
        [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadName:k_notificationCenter_menuDetailClose object:nil];
                
        // remove all Notification Messages
        [appDelegate.listOfNotifications removeAllObjects];
        
        // Not Photos Video in library ? then align and Init Auto Upload
        NSArray *recordsPhotoLibrary = [[NCManageDatabase sharedInstance] getPhotoLibraryWithPredicate:[NSPredicate predicateWithFormat:@"account == %@", appDelegate.activeAccount]];
        if ([recordsPhotoLibrary count] == 0) {
            [[NCAutoUpload sharedInstance] alignPhotoLibrary];
        }
        [[NCAutoUpload sharedInstance] initStateAutoUpload];
        
        NSLog(@"[LOG] Request Service Server Nextcloud");
        [[NCService sharedInstance] startRequestServicesServer];
        
        // Clear datasorce
        [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:_serverUrl ocId:nil action:k_action_NULL];
        
        // Read this folder
        [self readFileReloadFolder];
                
    } else {
        
        // reload datasource
        [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:_serverUrl ocId:nil action:k_action_NULL];
    }
    
    // Registeration push notification
    [appDelegate pushNotification];
    
    // Registeration domain File Provider
    if (@available(iOS 11, *) ) {
        if (k_fileProvider_domain) {
            [FileProviderDomain.sharedInstance registerDomain];
        } else {
            [FileProviderDomain.sharedInstance removeAllDomain];
        }        
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== NotificationCenter ====
#pragma --------------------------------------------------------------------------------------------

- (void)deleteFile:(NSNotification *)notification
{
    if (self.view.window == nil) { return; }
    
    NSDictionary *userInfo = notification.userInfo;
    tableMetadata *metadata = userInfo[@"metadata"];
    
    if ([metadata.serverUrl isEqualToString:self.serverUrl]) {
        if ([metadata.fileNameView.lowercaseString isEqualToString:k_fileNameRichWorkspace.lowercaseString]) {
            [self readFileReloadFolder];
        } else {
            if (self.searchController.isActive) {
                [self readFolder:self.serverUrl];
            } else {
                [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:self.serverUrl ocId:nil action:k_action_NULL];
            }
        }
    }
}

- (void)favoriteFile:(NSNotification *)notification
{
    if (self.view.window == nil) { return; }
    
    NSDictionary *userInfo = notification.userInfo;
    tableMetadata *metadata = userInfo[@"metadata"];
    NSInteger errorCode = [userInfo[@"errorCode"] integerValue];
    BOOL favorite = [userInfo[@"favorite"] boolValue];
    
    if (errorCode == 0) {
        _dateReadDataSource = nil;
        if (self.searchController.isActive) {
            [self readFolder:self.serverUrl];
        } else {
            [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:self.serverUrl ocId:metadata.ocId action:k_action_MOD];
        }
        
        if (metadata.directory && favorite) {
                       
            NSString *selector;
                       
            if ([CCUtility getFavoriteOffline])
                selector = selectorReadFolderWithDownload;
            else
                selector = selectorReadFolder;
                       
            [[CCSynchronize sharedSynchronize] readFolder:[CCUtility stringAppendServerUrl:self.serverUrl addFileName:metadata.fileName] selector:selector account:appDelegate.activeAccount];
        }
                   
        if (!metadata.directory && favorite && [CCUtility getFavoriteOffline]) {
                       
            metadata.favorite = favorite;
            metadata.session = k_download_session;
            metadata.sessionError = @"";
            metadata.sessionSelector = selectorDownloadSynchronize;
            metadata.status = k_metadataStatusWaitDownload;
                           
            // Add Metadata for Download
            [[NCManageDatabase sharedInstance] addMetadata:metadata];
            [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:self.serverUrl ocId:metadata.ocId action:k_action_MOD];
                    
            [appDelegate startLoadAutoDownloadUpload];
        }
    }
}

- (void)renameFile:(NSNotification *)notification {
    [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:self.serverUrl ocId:nil action:k_action_NULL];
}

- (void)createFolder:(NSNotification *)notification {
    if (self.view.window == nil) { return; }
    
    NSDictionary *userInfo = notification.userInfo;
    NSInteger errorCode = [userInfo[@"errorCode"] integerValue];
    
    if (errorCode == 0) {
        [self readFolder:self.serverUrl];
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== DZNEmptyDataSetSource ====
#pragma --------------------------------------------------------------------------------------------

- (BOOL)emptyDataSetShouldAllowScroll:(UIScrollView *)scrollView
{
    if (_loadingFolder)
        return NO;
    else
        return YES;
}

- (UIColor *)backgroundColorForEmptyDataSet:(UIScrollView *)scrollView
{
    return NCBrandColor.sharedInstance.backgroundView;
}

- (UIImage *)imageForEmptyDataSet:(UIScrollView *)scrollView
{
    if (self.searchController.isActive)
        return [CCGraphics changeThemingColorImage:[UIImage imageNamed:@"search"] width:300 height:300 color:NCBrandColor.sharedInstance.brandElement];
    else
        return [CCGraphics changeThemingColorImage:[UIImage imageNamed:@"folder"] width:300 height:300 color:NCBrandColor.sharedInstance.brandElement];
}

- (UIView *)customViewForEmptyDataSet:(UIScrollView *)scrollView
{
    if (_loadingFolder && refreshControl.isRefreshing == NO) {
    
        UIActivityIndicatorView *activityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        activityView.transform = CGAffineTransformMakeScale(1.5f, 1.5f);
        activityView.color = NCBrandColor.sharedInstance.brandElement;
        [activityView startAnimating];
        
        return activityView;
    }
    
    return nil;
}

- (NSAttributedString *)titleForEmptyDataSet:(UIScrollView *)scrollView
{
    NSString *text;
    
    if (self.searchController.isActive) {
        
        text = _noFilesSearchTitle;
        
    } else {
        
        text = [NSString stringWithFormat:@"%@", NSLocalizedString(@"_files_no_files_", nil)];
    }
    
    NSDictionary *attributes = @{NSFontAttributeName:[UIFont boldSystemFontOfSize:20.0f], NSForegroundColorAttributeName:[UIColor lightGrayColor]};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

- (NSAttributedString *)descriptionForEmptyDataSet:(UIScrollView *)scrollView
{
    NSString *text;
    
    if (self.searchController.isActive) {
        
        text = _noFilesSearchDescription;
        
    } else {
        
        text = [NSString stringWithFormat:@"\n%@", NSLocalizedString(@"_no_file_pull_down_", nil)];
    }
    
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    paragraph.alignment = NSTextAlignmentCenter;
    
    NSDictionary *attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:14.0], NSForegroundColorAttributeName: [UIColor lightGrayColor], NSParagraphStyleAttributeName: paragraph};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Text Field =====
#pragma --------------------------------------------------------------------------------------------

- (void)minCharTextFieldDidChange:(UITextField *)sender
{
    UIAlertController *alertController = (UIAlertController *)self.presentedViewController;
    
    if (alertController)
    {
        UITextField *fileName = alertController.textFields.firstObject;
        UIAlertAction *okAction = alertController.actions.lastObject;
        okAction.enabled = fileName.text.length > 0;
    }
}

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
    [CCUtility selectFileNameFrom:textField];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Graphic Window =====
#pragma --------------------------------------------------------------------------------------------

- (void)createRefreshControl
{
    refreshControl = [NCMainRefreshControl new];
    
    self.tableView.refreshControl = refreshControl;
    
    refreshControl.tintColor = NCBrandColor.sharedInstance.brandText;
    refreshControl.backgroundColor = NCBrandColor.sharedInstance.brand;
    
    [refreshControl addTarget:self action:@selector(refreshControlTarget) forControlEvents:UIControlEventValueChanged];
}

- (void)deleteRefreshControl
{
    [refreshControl endRefreshing];
    
    for (UIView *subview in [_tableView subviews]) {
        if (subview == refreshControl)
            [subview removeFromSuperview];
    }
    
    if (@available(iOS 10, *)) {
        self.tableView.refreshControl = nil;
    }
    
    refreshControl = nil;
}

- (void)refreshControlTarget
{
    [self readFolder:_serverUrl];
    
    // Actuate `Peek` feedback (weak boom)
    AudioServicesPlaySystemSound(1519);
}

- (void)setTitle
{
    if (_isSelectedMode) {
        
        NSUInteger totali = [sectionDataSource.allRecordsDataSource count];
        NSUInteger selezionati = [[self.tableView indexPathsForSelectedRows] count];
        
        self.navigationItem.titleView = nil;
        self.navigationItem.title = [NSString stringWithFormat:@"%@ : %lu / %lu", NSLocalizedString(@"_selected_", nil), (unsigned long)selezionati, (unsigned long)totali];

    } else {
        
        // we are in home : LOGO BRAND
        if ([_serverUrl isEqualToString:[CCUtility getHomeServerUrlActiveUrl:appDelegate.activeUrl]]) {
            
            self.navigationItem.title = nil;

            UIImage *image = [self getImageLogoHome];

            _imageTitleHome = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 60, 30)]; // IMAGE = 120 x 60
            _imageTitleHome.contentMode = UIViewContentModeScaleAspectFill;
            _imageTitleHome.translatesAutoresizingMaskIntoConstraints = NO;
            _imageTitleHome.image = image;
            
            // backbutton
            self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] style:UIBarButtonItemStylePlain target:nil action:nil];
            
            [_imageTitleHome setUserInteractionEnabled:YES];
            UITapGestureRecognizer *singleTap =  [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(menuLogo:)];
            [singleTap setNumberOfTapsRequired:1];
            [_imageTitleHome addGestureRecognizer:singleTap];
            
            self.navigationItem.titleView = _imageTitleHome;
            
        } else {
            
            self.navigationItem.title = _titleMain;
            self.navigationItem.titleView = nil;
        }
    }
}

- (UIImage *)getImageLogoHome
{
    UIImage *image = [UIImage imageNamed:@"themingLogo"];
    
    tableCapabilities *capabilities = [[NCManageDatabase sharedInstance] getCapabilitesWithAccount:appDelegate.activeAccount];
    if ([NCBrandOptions sharedInstance].use_themingColor && [capabilities.themingColorText isEqualToString:@"#000000"] && [UIImage imageNamed:@"themingLogoBlack"]) {
        image = [UIImage imageNamed:@"themingLogoBlack"];
    }
   
    if ([NCBrandOptions sharedInstance].use_themingLogo) {
        
        image = [UIImage imageWithContentsOfFile:[NSString stringWithFormat:@"%@/%@-themingLogo.png", [CCUtility getDirectoryUserData], [CCUtility getStringUser:appDelegate.activeUser activeUrl:appDelegate.activeUrl]]];
        if (image == nil) image = [UIImage imageNamed:@"themingLogo"];
    }
        
    if ([appDelegate.reachability isReachable] == NO) {
            
        return [CCGraphics changeThemingColorImage:[UIImage imageNamed:@"nonetwork"] width:50 height:50 color:NCBrandColor.sharedInstance.icon];
            
    } else {
        
        return image;
    }
}

- (void)setUINavigationBarDefault
{
    UIBarButtonItem *buttonMore, *buttonNotification, *buttonSelect;
    
    // =
    buttonMore = [[UIBarButtonItem alloc] initWithImage:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"navigationSort"] width:50 height:50 color:NCBrandColor.sharedInstance.textView] style:UIBarButtonItemStylePlain target:self action:@selector(toggleReMainMenu)];
    buttonMore.enabled = true;
    
    buttonSelect = [[UIBarButtonItem alloc] initWithImage:[CCGraphics changeThemingColorImage:[UIImage imageNamed:@"select"] width:50 height:50 color:NCBrandColor.sharedInstance.textView] style:UIBarButtonItemStylePlain target:self action:@selector(tableViewToggle)];
    buttonSelect.enabled = true;
    
    // <
    self.navigationController.navigationBar.hidden = NO;
    
    // Notification
    if ([appDelegate.listOfNotifications count] > 0) {
        
        buttonNotification = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"notification"] style:UIBarButtonItemStylePlain target:self action:@selector(viewNotification)];
        buttonNotification.tintColor = NCBrandColor.sharedInstance.brandText;
        buttonNotification.enabled = true;
    }
    
    if (buttonNotification)
        self.navigationItem.rightBarButtonItems = [[NSArray alloc] initWithObjects:buttonMore, buttonSelect, buttonNotification, nil];
    else
        self.navigationItem.rightBarButtonItems = [[NSArray alloc] initWithObjects:buttonMore, buttonSelect, nil];
    
    self.navigationItem.leftBarButtonItem = nil;
}

- (void)setUINavigationBarSelected
{    
    UIImage *icon = [UIImage imageNamed:@"navigationMore"];
    UIBarButtonItem *buttonMore = [[UIBarButtonItem alloc] initWithImage:icon style:UIBarButtonItemStylePlain target:self action:@selector(toggleReSelectMenu)];

    UIBarButtonItem *leftButton = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"_cancel_", nil) style:UIBarButtonItemStylePlain target:self action:@selector(cancelSelect)];
    
    self.navigationItem.leftBarButtonItem = leftButton;
    self.navigationItem.rightBarButtonItems = [[NSArray alloc] initWithObjects:buttonMore, nil];
}

- (void)cancelSelect
{
    [self tableViewSelect:false];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Document Picker =====
#pragma --------------------------------------------------------------------------------------------

- (void)documentMenuWasCancelled:(UIDocumentMenuViewController *)documentMenu
{
    NSLog(@"[LOG] Cancelled");
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller
{
    NSLog(@"[LOG] Cancelled");
}

- (void)documentMenu:(UIDocumentMenuViewController *)documentMenu didPickDocumentPicker:(UIDocumentPickerViewController *)documentPicker
{
    documentPicker.delegate = self;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url
{
    if (controller.documentPickerMode == UIDocumentPickerModeImport) {
        
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        __block NSError *error;
        
        [coordinator coordinateReadingItemAtURL:url options:NSFileCoordinatorReadingForUploading error:&error byAccessor:^(NSURL *newURL) {
            
            NSString *serverUrl = [appDelegate getTabBarControllerActiveServerUrl];
            NSString *fileName =  [[NCUtility sharedInstance] createFileName:[url lastPathComponent] serverUrl:serverUrl account:appDelegate.activeAccount];
            NSString *ocId = [CCUtility createMetadataIDFromAccount:appDelegate.activeAccount serverUrl:serverUrl fileNameView:fileName directory:false];
            NSData *data = [NSData dataWithContentsOfURL:newURL];
            
            if (data && error == nil) {
                
                if ([data writeToFile:[CCUtility getDirectoryProviderStorageOcId:ocId fileNameView:fileName] options:NSDataWritingAtomic error:&error]) {
                    
                    tableMetadata *metadataForUpload = [tableMetadata new];
                    
                    metadataForUpload.account = appDelegate.activeAccount;
                    metadataForUpload.date = [NSDate new];
                    metadataForUpload.ocId = ocId;
                    metadataForUpload.fileName = fileName;
                    metadataForUpload.fileNameView = fileName;
                    metadataForUpload.serverUrl = serverUrl;
                    metadataForUpload.session = k_upload_session;
                    metadataForUpload.sessionSelector = selectorUploadFile;
                    metadataForUpload.size = data.length;
                    metadataForUpload.status = k_metadataStatusWaitUpload;
                    
                    [[NCManageDatabase sharedInstance] addMetadata:metadataForUpload];
                    [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:self.serverUrl ocId:nil action:k_action_NULL];
                        
                    [appDelegate startLoadAutoDownloadUpload];
                    
                } else {
                                        
                    [[NCContentPresenter shared] messageNotification:@"_error_" description:error.description delay:k_dismissAfterSecond type:messageTypeError errorCode:error.code];
                }
                
            } else {
                
                [[NCContentPresenter shared] messageNotification:@"_error_" description:@"_read_file_error_" delay:k_dismissAfterSecond type:messageTypeError errorCode:error.code];
            }
        }];
    }
}

- (void)openImportDocumentPicker
{
    UIDocumentMenuViewController *documentProviderMenu = [[UIDocumentMenuViewController alloc] initWithDocumentTypes:@[@"public.data"] inMode:UIDocumentPickerModeImport];
    
    documentProviderMenu.modalPresentationStyle = UIModalPresentationFormSheet;
    documentProviderMenu.popoverPresentationController.sourceView = self.tabBarController.tabBar;
    documentProviderMenu.popoverPresentationController.sourceRect = self.tabBarController.tabBar.bounds;
    documentProviderMenu.delegate = self;
    
    [self presentViewController:documentProviderMenu animated:YES completion:nil];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Assets Picker =====
#pragma --------------------------------------------------------------------------------------------

-(void)dismissFormUploadAssets
{
    [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:self.serverUrl ocId:nil action:k_action_NULL];
}

- (void)openAssetsPickerController
{
    NCPhotosPickerViewController *viewController = [[NCPhotosPickerViewController alloc] init:self maxSelectedAssets:100 singleSelectedMode:false];
    
    [viewController openPhotosPickerViewControllerWithPhAssets:^(NSArray<PHAsset *> * _Nullable assets, NSArray<NSURL *> * urls) {
        if (assets.count > 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void) {
                NSString *serverUrl = [appDelegate getTabBarControllerActiveServerUrl];
                
                NCCreateFormUploadAssets *form = [[NCCreateFormUploadAssets alloc] initWithServerUrl:serverUrl assets:(NSMutableArray *)assets urls:(NSMutableArray *)urls cryptated:NO session:k_upload_session delegate:self];
                
                UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:form];
                [navigationController setModalPresentationStyle:UIModalPresentationFormSheet];
                
                [self presentViewController:navigationController animated:YES completion:nil];
            });
        }
    }];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Save selected File =====
#pragma --------------------------------------------------------------------------------------------

- (void)saveToPhotoAlbum:(tableMetadata *)metadata
{
    NSString *fileNamePath = [CCUtility getDirectoryProviderStorageOcId:metadata.ocId fileNameView:metadata.fileNameView];
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    
    if ([metadata.typeFile isEqualToString: k_metadataTypeFile_image] && status == PHAuthorizationStatusAuthorized) {
        
        UIImage *image = [UIImage imageWithContentsOfFile:fileNamePath];
        
        if (image)
            UIImageWriteToSavedPhotosAlbum(image, self, @selector(saveSelectedFilesSelector: didFinishSavingWithError: contextInfo:), nil);
        else
            [[NCContentPresenter shared] messageNotification:@"_save_selected_files_" description:@"_file_not_saved_cameraroll_" delay:k_dismissAfterSecond type:messageTypeError errorCode:k_CCErrorInternalError];
    }
    
    if ([metadata.typeFile isEqualToString: k_metadataTypeFile_video] && status == PHAuthorizationStatusAuthorized) {
        
        if (UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(fileNamePath)) {
            
            UISaveVideoAtPathToSavedPhotosAlbum(fileNamePath, self, @selector(saveSelectedFilesSelector: didFinishSavingWithError: contextInfo:), nil);
        } else {
            [[NCContentPresenter shared] messageNotification:@"_save_selected_files_" description:@"_file_not_saved_cameraroll_" delay:k_dismissAfterSecond type:messageTypeError errorCode:k_CCErrorInternalError];
        }
    }
    
    if (status != PHAuthorizationStatusAuthorized) {
        
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"_access_photo_not_enabled_", nil) message:NSLocalizedString(@"_access_photo_not_enabled_msg_", nil) preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"_ok_", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {}];
        
        [alertController addAction:okAction];
        [self presentViewController:alertController animated:YES completion:nil];
    }
}

- (void)saveSelectedFilesSelector:(NSString *)path didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo
{
    if (error) {
        [[NCContentPresenter shared] messageNotification:@"_save_selected_files_" description:@"_file_not_saved_cameraroll_" delay:k_dismissAfterSecond type:messageTypeError errorCode:error.code];
    }
}

- (void)saveSelectedFiles
{
    if (_isSelectedMode && [_selectedocIdsMetadatas count] == 0)
        return;

    NSLog(@"[LOG] Start download selected files ...");
    
    [_hud visibleHudTitle:@"" mode:MBProgressHUDModeIndeterminate color:nil];
    
    NSArray *metadatas = [self getMetadatasFromSelectedRows:[self.tableView indexPathsForSelectedRows]];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.01 * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void) {
        
        for (tableMetadata *metadata in metadatas) {
            
            if (metadata.directory == NO && ([metadata.typeFile isEqualToString: k_metadataTypeFile_image] || [metadata.typeFile isEqualToString: k_metadataTypeFile_video])) {
                
                metadata.session = k_download_session;
                metadata.sessionError = @"";
                metadata.sessionSelector = selectorSave;
                metadata.status = k_metadataStatusWaitDownload;
                    
                // Add Metadata for Download
                [[NCManageDatabase sharedInstance] addMetadata:metadata];
                
                [appDelegate startLoadAutoDownloadUpload];
            }
        }
        
        [_hud hideHud];
        
        [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:self.serverUrl ocId:nil action:k_action_NULL];
    });
    
    [self tableViewSelect:false];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== View Notification  ====
#pragma --------------------------------------------------------------------------------------------

- (void)viewNotification
{
    if ([appDelegate.listOfNotifications count] > 0) {
        
        CCNotification *notificationVC = [[UIStoryboard storyboardWithName:@"CCNotification" bundle:nil] instantiateViewControllerWithIdentifier:@"CCNotification"];
        
        [notificationVC setModalPresentationStyle:UIModalPresentationFormSheet];
        
        [self presentViewController:notificationVC animated:YES completion:nil];
    }
}

#pragma mark -
#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Peek & Pop  =====
#pragma --------------------------------------------------------------------------------------------

- (UIViewController *)previewingContext:(id<UIViewControllerPreviewing>)previewingContext viewControllerForLocation:(CGPoint)location
{
    CGPoint convertedLocation = [self.view convertPoint:location toView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:convertedLocation];
    tableMetadata *metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
    
    CCCellMain *cell = [self.tableView cellForRowAtIndexPath:indexPath];
        
    if (cell) {
        previewingContext.sourceRect = cell.frame;
        CCPeekPop *viewController = [[UIStoryboard storyboardWithName:@"CCPeekPop" bundle:nil] instantiateViewControllerWithIdentifier:@"PeekPopImagePreview"];
            
        viewController.metadata = metadata;
        viewController.imageFile = cell.file.image;
        viewController.showOpenIn = true;
        viewController.showShare = true;
        if ([metadata.typeFile isEqualToString: k_metadataTypeFile_document]) {
            viewController.showOpenInternalViewer = true;
        }
        
        return viewController;
    }
    
    return nil;
}

- (void)previewingContext:(id<UIViewControllerPreviewing>)previewingContext commitViewController:(UIViewController *)viewControllerToCommit
{
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:previewingContext.sourceRect.origin];
    
    [self tableView:self.tableView didSelectRowAtIndexPath:indexPath];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== Download ====
#pragma --------------------------------------------------------------------------------------------

- (void)downloadSelectedFilesFolders
{
    if (_isSelectedMode && [_selectedocIdsMetadatas count] == 0)
        return;

    NSLog(@"[LOG] Start download selected ...");
    
    [_hud visibleHudTitle:NSLocalizedString(@"_downloading_progress_", nil) mode:MBProgressHUDModeIndeterminate color:nil];
    
    NSArray *selectedMetadatas = [self getMetadatasFromSelectedRows:[self.tableView indexPathsForSelectedRows]];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void) {
        
        for (tableMetadata *metadata in selectedMetadatas) {
            
            if (metadata.directory) {
                
                [[CCSynchronize sharedSynchronize] readFolder:[CCUtility stringAppendServerUrl:metadata.serverUrl addFileName:metadata.fileName] selector:selectorReadFolderWithDownload account:appDelegate.activeAccount];
                    
            } else {
                
                [[CCSynchronize sharedSynchronize] readFile:metadata.ocId fileName:metadata.fileName serverUrl:metadata.serverUrl selector:selectorReadFileWithDownload account:appDelegate.activeAccount];
            }
        }
        
        [_hud hideHud];
    });
    
    [self tableViewSelect:false];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Upload new Photos/Videos =====
#pragma --------------------------------------------------------------------------------------------

//
// This procedure with performSelectorOnMainThread it's necessary after (Bridge) for use the function "Sync" in OCNetworking
//
- (void)uploadFileAsset:(NSMutableArray *)assets urls:(NSMutableArray *)urls serverUrl:(NSString *)serverUrl useSubFolder:(BOOL)useSubFolder session:(NSString *)session
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
 
        NSString *autoUploadPath = [[NCManageDatabase sharedInstance] getAccountAutoUploadPath:appDelegate.activeUrl];

        // if request create the folder for Auto Upload & the subfolders
        if ([autoUploadPath isEqualToString:serverUrl])
            if (![[NCAutoUpload sharedInstance] createAutoUploadFolderWithSubFolder:useSubFolder assets:(PHFetchResult *)assets selector:selectorUploadFile])
                return;
    
        dispatch_async(dispatch_get_main_queue(), ^{
            [self uploadFileAsset:assets urls:urls serverUrl:serverUrl autoUploadPath:autoUploadPath useSubFolder:useSubFolder session:session];
        });
    });
}

- (void)uploadFileAsset:(NSArray *)assets urls:(NSArray *)urls serverUrl:(NSString *)serverUrl autoUploadPath:(NSString *)autoUploadPath useSubFolder:(BOOL)useSubFolder session:(NSString *)session
{
    NSMutableArray *metadatas = [NSMutableArray new];
    NSMutableArray *metadatasMOV = [NSMutableArray new];
    NSMutableArray *metadatasConflict = [NSMutableArray new];

    for (PHAsset *asset in assets) {
        
        NSString *fileName = [CCUtility createFileName:[asset valueForKey:@"filename"] fileDate:asset.creationDate fileType:asset.mediaType keyFileName:k_keyFileNameMask keyFileNameType:k_keyFileNameType keyFileNameOriginal:k_keyFileNameOriginal];
        
        NSDate *assetDate = asset.creationDate;
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        
        // Create serverUrl if use sub folder
        if (useSubFolder) {
            
            [formatter setDateFormat:@"yyyy"];
            NSString *yearString = [formatter stringFromDate:assetDate];
        
            [formatter setDateFormat:@"MM"];
            NSString *monthString = [formatter stringFromDate:assetDate];
            
            serverUrl = [NSString stringWithFormat:@"%@/%@/%@", autoUploadPath, yearString, monthString];
        }
        
        // Check if is in upload
        NSArray *isRecordInSessions = [[NCManageDatabase sharedInstance] getMetadatasWithPredicate:[NSPredicate predicateWithFormat:@"account == %@ AND serverUrl == %@ AND fileName == %@ AND session != ''", appDelegate.activeAccount, serverUrl, fileName] sorted:nil ascending:NO];
        if ([isRecordInSessions count] > 0)
            continue;
        
        // Prepare record metadata
        tableMetadata *metadataForUpload = [tableMetadata new];

        metadataForUpload.account = appDelegate.activeAccount;
        metadataForUpload.assetLocalIdentifier = asset.localIdentifier;
        metadataForUpload.date = [NSDate new];
        metadataForUpload.ocId = [CCUtility createMetadataIDFromAccount:appDelegate.activeAccount serverUrl:serverUrl fileNameView:fileName directory:false];
        metadataForUpload.fileName = fileName;
        metadataForUpload.fileNameView = fileName;
        metadataForUpload.serverUrl = serverUrl;
        metadataForUpload.session = session;
        metadataForUpload.sessionSelector = selectorUploadFile;
        metadataForUpload.size = [[NCUtility sharedInstance] getFileSizeWithAsset:asset];
        metadataForUpload.status = k_metadataStatusWaitUpload;
        [CCUtility insertTypeFileIconName:fileName metadata:metadataForUpload];
        
        // verify exists conflict
        NSString *fileNameExtension = [fileName pathExtension].lowercaseString;
        NSString *fileNameWithoutExtension = [fileName stringByDeletingPathExtension];
        NSString *fileNameConflict = fileName;
        
        if ([fileNameExtension isEqualToString:@"heic"] && [CCUtility getFormatCompatibility]) {
            fileNameConflict = [fileNameWithoutExtension stringByAppendingString:@".jpg"];
        }
        tableMetadata *metadata = [[NCManageDatabase sharedInstance] getMetadataWithPredicate:[NSPredicate predicateWithFormat:@"account == %@ AND serverUrl == %@ AND fileNameView == %@", appDelegate.activeAccount, serverUrl, fileNameConflict]];
        if (metadata) {
            [metadatasConflict addObject:metadataForUpload];
        } else {
            [metadatas addObject:metadataForUpload];
        }
                    
        // Add Medtadata MOV LIVE PHOTO for upload
        if ((asset.mediaSubtypes == PHAssetMediaSubtypePhotoLive || asset.mediaSubtypes == PHAssetMediaSubtypePhotoLive+PHAssetMediaSubtypePhotoHDR) && CCUtility.getMOVLivePhoto && urls.count == assets.count) {
                
            NSUInteger index = [assets indexOfObject:asset];
            NSURL *url = [urls objectAtIndex:index];
            tableMetadata *metadataMOVForUpload = [tableMetadata new];
            NSString *fileNameNoExt = [fileName stringByDeletingPathExtension];
            NSString *fileName = [NSString stringWithFormat:@"%@.mov", fileNameNoExt];
            unsigned long long fileSize = [[[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:nil] fileSize];

            metadataMOVForUpload.account = appDelegate.activeAccount;
            metadataMOVForUpload.date = [NSDate new];
            metadataMOVForUpload.ocId = [CCUtility createMetadataIDFromAccount:appDelegate.activeAccount serverUrl:serverUrl fileNameView:fileName directory:false];
            metadataMOVForUpload.fileName = fileName;
            metadataMOVForUpload.fileNameView = fileName;
            metadataMOVForUpload.serverUrl = serverUrl;
            metadataMOVForUpload.session = session;
            metadataMOVForUpload.sessionSelector = selectorUploadFile;
            metadataMOVForUpload.size = fileSize;
            metadataMOVForUpload.status = k_metadataStatusWaitUpload;
            
            // Prepare file and directory
            [CCUtility moveFileAtPath:url.path toPath:[CCUtility getDirectoryProviderStorageOcId:metadataMOVForUpload.ocId fileNameView:fileName]];
            
            [metadatasMOV addObject:metadataMOVForUpload];
        }
    }
    
    // Verify if file(s) exists
    if (metadatasConflict.count > 0) {
        
        NCCreateFormUploadConflict *conflict = [[UIStoryboard storyboardWithName:@"NCCreateFormUploadConflict" bundle:nil] instantiateInitialViewController];
        conflict.delegate = self;
        conflict.metadatas = metadatas;
        conflict.metadatasMOV = metadatasMOV;
        conflict.metadatasConflict = metadatasConflict;
        
        [self presentViewController:conflict animated:YES completion:nil];
        
    } else {
        
        [[NCManageDatabase sharedInstance] addMetadatas:metadatas];
        [[NCManageDatabase sharedInstance] addMetadatas:metadatasMOV];
        
        [appDelegate startLoadAutoDownloadUpload];
        [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:self.serverUrl ocId:nil action:k_action_NULL];
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== NCCreateFormUploadConflictDelegate ====
#pragma --------------------------------------------------------------------------------------------

- (void)dismissCreateFormUploadConflictWithMetadatas:(NSArray *)metadatas
{
    if (metadatas.count > 0) {
        [[NCManageDatabase sharedInstance] addMetadatas:metadatas];
        
        [appDelegate startLoadAutoDownloadUpload];
        [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:self.serverUrl ocId:nil action:k_action_NULL];
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== Read File ====
#pragma --------------------------------------------------------------------------------------------

- (void)readFileReloadFolder
{
    if (!_serverUrl || !appDelegate.activeAccount || appDelegate.maintenanceMode)
        return;
    
    // RichWorkspace
    tableDirectory *directory = [[NCManageDatabase sharedInstance] getTableDirectoryWithPredicate:[NSPredicate predicateWithFormat:@"account == %@ AND serverUrl == %@", appDelegate.activeAccount, self.serverUrl]];
    self.richWorkspaceText = directory.richWorkspace;
    [self setTableViewHeader];
    
    // Load Datasource
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.001 * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void) {
        [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:self.serverUrl ocId:nil action:k_action_NULL];
    });
    
    [[NCCommunication sharedInstance] readFileOrFolderWithServerUrlFileName:self.serverUrl depth:@"0" account:appDelegate.activeAccount completionHandler:^(NSString *account, NSArray*files, NSInteger errorCode, NSString *errorMessage) {
          
        if (errorCode == 0 && [account isEqualToString:appDelegate.activeAccount] && files.count > 0) {
            
            tableMetadata *metadata = [[NCNetworking sharedInstance] convertFile:files[0] urlString:appDelegate.activeUrl serverUrl:self.serverUrl fileName:@"" user:appDelegate.activeUser];
            
            // Rich Workspace
            [[NCManageDatabase sharedInstance] setDirectoryWithOcId:metadata.ocId serverUrl:self.serverUrl richWorkspace:metadata.richWorkspace account:account];
            self.richWorkspaceText = metadata.richWorkspace;
            [self setTableViewHeader];
            
            tableDirectory *directory = [[NCManageDatabase sharedInstance] getTableDirectoryWithPredicate:[NSPredicate predicateWithFormat:@"account == %@ AND serverUrl == %@", account, metadata.serverUrl]];
            
            // Read folder: No record, Change etag or BLINK
            if ([sectionDataSource.allRecordsDataSource count] == 0 || [metadata.etag isEqualToString:directory.etag] == NO || self.blinkFileNamePath != nil) {
                [self readFolder:self.serverUrl];
            }
            
        } else if (errorCode != 0) {
            [[NCContentPresenter shared] messageNotification:@"_error_" description:errorMessage delay:k_dismissAfterSecond type:messageTypeError errorCode:errorCode];
        } else {
            NSLog(@"[LOG] It has been changed user during networking process, error.");
        }
    }];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== Read Folder ====
#pragma --------------------------------------------------------------------------------------------

- (void)insertMetadatasWithAccount:(NSString *)account serverUrl:(NSString *)serverUrl metadataFolder:(tableMetadata *)metadataFolder metadatas:(NSArray *)metadatas
{
    // stoprefresh
    [refreshControl endRefreshing];
    
    // save metadataFolder
    _metadataFolder = metadataFolder;
    
    tableAccount *tableAccount = [[NCManageDatabase sharedInstance] getAccountWithPredicate:[NSPredicate predicateWithFormat:@"account == %@", account]];
    if (tableAccount == nil) {
        return;
    }
    
    if (self.searchController.isActive == NO) {
        
        [[NCManageDatabase sharedInstance] setDirectoryWithServerUrl:serverUrl serverUrlTo:nil etag:metadataFolder.etag ocId:metadataFolder.ocId encrypted:metadataFolder.e2eEncrypted richWorkspace:nil account:account];
        [[NCManageDatabase sharedInstance] deleteMetadataWithPredicate:[NSPredicate predicateWithFormat:@"account == %@ AND serverUrl == %@ AND status == %d", account, serverUrl, k_metadataStatusNormal]];
        [[NCManageDatabase sharedInstance] setDateReadDirectoryWithServerUrl:serverUrl account:account];
    }
    
    NSArray *metadatasInDownload = [[NCManageDatabase sharedInstance] getMetadatasWithPredicate:[NSPredicate predicateWithFormat:@"account == %@ AND serverUrl == %@ AND (status == %d OR status == %d OR status == %d OR status == %d)", account, serverUrl, k_metadataStatusWaitDownload, k_metadataStatusInDownload, k_metadataStatusDownloading, k_metadataStatusDownloadError] sorted:nil ascending:NO];
    
    // insert in Database
    NSMutableArray *metadatasToInsertInDB = (NSMutableArray *)[[NCManageDatabase sharedInstance] addMetadatas:metadatas];
    // insert in Database the /
    if (metadataFolder != nil) {
        _metadataFolder = [[NCManageDatabase sharedInstance] addMetadata:metadataFolder];
    }
    // reinsert metadatas in Download
    if (metadatasInDownload) {
        [[NCManageDatabase sharedInstance] addMetadatas:metadatasInDownload];
    }
    
    // File is changed ??
    if (!self.searchController.isActive && metadatasToInsertInDB) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            [[CCSynchronize sharedSynchronize] verifyChangeMedatas:metadatasToInsertInDB serverUrl:serverUrl account:account withDownload:NO];
        });
    }
    // Search Mode
    if (self.searchController.isActive) {
        
        // Fix managed -> Unmanaged _searchResultMetadatas
        if (metadatasToInsertInDB)
            _searchResultMetadatas = [[NSMutableArray alloc] initWithArray:metadatasToInsertInDB];
        
        [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:serverUrl ocId:nil action:k_action_NULL];
    }
    
    // this is the same directory
    if ([serverUrl isEqualToString:_serverUrl] && !self.searchController.isActive) {
        
        // reload
        [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:serverUrl ocId:nil action:k_action_NULL];
        
        [self tableViewReloadData];
    }
    
    // E2EE Is encrypted folder get metadata
    if (_metadataFolder.e2eEncrypted) {
        NSString *metadataFolderocId = metadataFolder.ocId;
        // Read Metadata
        if ([CCUtility isEndToEndEnabled:account]) {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                NSString *metadata;
                NSError *error = [[NCNetworkingEndToEnd sharedManager] getEndToEndMetadata:&metadata ocId:metadataFolderocId user:tableAccount.user userID:tableAccount.userID password:[CCUtility getPassword:tableAccount.account] url:tableAccount.url];
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (error) {
                        if (error.code != kOCErrorServerPathNotFound)
                            [[NCContentPresenter shared] messageNotification:@"_e2e_error_get_metadata_" description:error.localizedDescription delay:k_dismissAfterSecond type:messageTypeError errorCode:error.code];
                    } else {
                        if ([[NCEndToEndMetadata sharedInstance] decoderMetadata:metadata privateKey:[CCUtility getEndToEndPrivateKey:account] serverUrl:self.serverUrl account:account url:tableAccount.url] == false)
                            [[NCContentPresenter shared] messageNotification:@"_error_e2ee_" description:@"_e2e_error_decode_metadata_" delay:k_dismissAfterSecond type:messageTypeError errorCode:error.code];
                        else
                            [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:serverUrl ocId:nil action:k_action_NULL];
                    }
                });
            });
        } else {
            [[NCContentPresenter shared] messageNotification:@"_info_" description:@"_e2e_goto_settings_for_enable_" delay:k_dismissAfterSecond type:messageTypeInfo errorCode:0];
        }
    }
    
    // rewrite title
    [self setTitle];
}

- (void)readFolder:(NSString *)serverUrl
{
    // init control
    if (!serverUrl || !appDelegate.activeAccount || appDelegate.maintenanceMode) {
        [refreshControl endRefreshing];
        return;
    }
    
    // Search Mode
    if (self.searchController.isActive) {
        
        [[NCManageDatabase sharedInstance] clearDateReadWithServerUrl:serverUrl account:appDelegate.activeAccount];
            
        _searchFileName = @""; // forced reload searchg
        
        [self updateSearchResultsForSearchController:self.searchController];
        
        return;
    }
    
    _loadingFolder = YES;

    [self tableViewReloadData];
    
    [[OCNetworking sharedManager] readFolderWithAccount:appDelegate.activeAccount serverUrl:serverUrl depth:@"1" completion:^(NSString *account, NSArray *metadatas, tableMetadata *metadataFolder, NSString *message, NSInteger errorCode) {
        
        if (errorCode == 0 && [account isEqualToString:appDelegate.activeAccount]) {
            [self insertMetadatasWithAccount:account serverUrl:serverUrl metadataFolder:metadataFolder metadatas:metadatas];
        } else if (errorCode != 0) {
            [[NCContentPresenter shared] messageNotification:@"_error_" description:message delay:k_dismissAfterSecond type:messageTypeError errorCode:errorCode];
        } else {
            NSLog(@"[LOG] It has been changed user during networking process, error.");
        }
        
        _loadingFolder = NO;
    }];
}

#pragma mark -
#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Search =====
#pragma --------------------------------------------------------------------------------------------

- (void)searchStartTimer
{
    if (self.searchController.isActive == false) {
        return;
    }
    
    NSString *startDirectory = [CCUtility getHomeServerUrlActiveUrl:appDelegate.activeUrl];
    
    [[OCNetworking sharedManager] searchWithAccount:appDelegate.activeAccount fileName:_searchFileName serverUrl:startDirectory contentType:nil lteDateLastModified:nil gteDateLastModified:nil depth:@"infinity" completion:^(NSString *account, NSArray *metadatas, NSString *message, NSInteger errorCode) {
       
        if (errorCode == 0 && [account isEqualToString:appDelegate.activeAccount]) {
            
#if TARGET_OS_SIMULATOR
            tableCapabilities *capabilities = [[NCManageDatabase sharedInstance] getCapabilitesWithAccount:account];
            if (capabilities.isFulltextsearchEnabled) {
                [[OCNetworking sharedManager] fullTextSearchWithAccount:appDelegate.activeAccount text:_searchFileName page:1 completion:^(NSString *account, NSArray *items, NSString *message, NSInteger errorCode) {
                    NSLog(@"x");
                }];
            }
#endif
            
            _searchResultMetadatas = [[NSMutableArray alloc] initWithArray:metadatas];
            [self insertMetadatasWithAccount:appDelegate.activeAccount serverUrl:_serverUrl metadataFolder:nil metadatas:_searchResultMetadatas];
            
        } else {
            
            if (errorCode != 0) {
                [[NCContentPresenter shared] messageNotification:@"_error_" description:message delay:k_dismissAfterSecond type:messageTypeError errorCode:errorCode];
            } else {
                NSLog(@"[LOG] It has been changed user during networking process, error.");
            }
            
            _searchFileName = @"";
        }
        
    }];
    
    _noFilesSearchTitle = @"";
    _noFilesSearchDescription = NSLocalizedString(@"_search_in_progress_", nil);
    
    [self.tableView reloadEmptyDataSet];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController
{
    // Color text "Cancel"
    [[UIBarButtonItem appearanceWhenContainedInInstancesOfClasses:@[[UISearchBar class]]] setTintColor:NCBrandColor.sharedInstance.brandText];
    
    if (searchController.isActive) {
        [self deleteRefreshControl];
        
        NSString *fileName = [CCUtility removeForbiddenCharactersServer:searchController.searchBar.text];
        
        if (fileName.length >= k_minCharsSearch && [fileName isEqualToString:_searchFileName] == NO) {
            
            _searchFileName = fileName;
            
            // First : filter
                
            NSArray *records = [[NCManageDatabase sharedInstance] getMetadatasWithPredicate:[NSPredicate predicateWithFormat:@"account == %@ AND serverUrl == %@ AND fileNameView CONTAINS[cd] %@", appDelegate.activeAccount, _serverUrl, fileName] sorted:nil ascending:NO];
                
            [_searchResultMetadatas removeAllObjects];
            for (tableMetadata *record in records)
                [_searchResultMetadatas addObject:record];
            
            [self insertMetadatasWithAccount:appDelegate.activeAccount serverUrl:_serverUrl metadataFolder:nil metadatas:_searchResultMetadatas];
        
            // Version >= 12
            if ([[NCManageDatabase sharedInstance] getServerVersionWithAccount:appDelegate.activeAccount] >= 12) {
                
                [_timerWaitInput invalidate];
                _timerWaitInput = [NSTimer scheduledTimerWithTimeInterval:1.5 target:self selector:@selector(searchStartTimer) userInfo:nil repeats:NO];
            }
        }
        
        if (_searchResultMetadatas.count == 0 && fileName.length == 0) {

            [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:self.serverUrl ocId:nil action:k_action_NULL];
        }
        
    } else {
        
        [self createRefreshControl];

        [self reloadDatasource:self.serverUrl ocId:nil action:k_action_NULL];
    }
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar
{
    [self cancelSearchBar];
}

- (void)cancelSearchBar
{
    if (self.searchController.active) {
        
        [self.searchController setActive:NO];
    
        _searchFileName = @"";
        _dateReadDataSource = nil;
        _searchResultMetadatas = [NSMutableArray new];
        
        [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:self.serverUrl ocId:nil action:k_action_NULL];
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void) {
        [self setTableViewHeader];
    });
}

#pragma mark -
#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Delete File or Folder =====
#pragma --------------------------------------------------------------------------------------------

- (void)deleteMetadatas
{
    if (_isSelectedMode && [_selectedocIdsMetadatas count] == 0)
        return;
     
    if ([_selectedocIdsMetadatas count] > 0) {
        [appDelegate.arrayDeleteMetadata addObjectsFromArray:[_selectedocIdsMetadatas allValues]];
    } else {
        [appDelegate.arrayDeleteMetadata addObject:self.metadata];
    }
    
    [[NCNetworking sharedInstance] deleteMetadata:appDelegate.arrayDeleteMetadata.firstObject user:appDelegate.activeUser userID:appDelegate.activeUserID password:appDelegate.activePassword url:appDelegate.activeUrl completion:^(NSInteger errorCode, NSString *errorDescription) { }];
    [appDelegate.arrayDeleteMetadata removeObjectAtIndex:0];
    
    // remove optimization
    _dateReadDataSource = nil;
    
    // End Select Table View
    [self tableViewSelect:false];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Move =====
#pragma --------------------------------------------------------------------------------------------

- (void)moveFileOrFolderMetadata:(tableMetadata *)metadata serverUrlTo:(NSString *)serverUrlTo numFile:(NSInteger)numFile ofFile:(NSInteger)ofFile
{
    // verify permission
    BOOL permission = [[NCUtility sharedInstance] permissionsContainsString:metadata.permissions permissions:k_permission_can_move];
    if (![metadata.permissions isEqualToString:@""] && permission == false) {
        [[NCContentPresenter shared] messageNotification:@"_error_" description:@"_no_permission_modify_file_" delay:k_dismissAfterSecond type:messageTypeError errorCode:k_CCErrorInternalError];
        return;
    }
    
    NSString *serverUrlFileName = [NSString stringWithFormat:@"%@/%@", serverUrlTo, metadata.fileName];
           
    [[NCCommunication sharedInstance] readFileOrFolderWithServerUrlFileName:serverUrlFileName depth:@"0" account:appDelegate.activeAccount completionHandler:^(NSString *account, NSArray*files, NSInteger errorCode, NSString *errorDescription) {
                       
        if (errorCode == 0 && [account isEqualToString:appDelegate.activeAccount]) {
            
            UIAlertController * alert= [UIAlertController alertControllerWithTitle:NSLocalizedString(@"_error_", nil) message:NSLocalizedString(@"_file_already_exists_", nil) preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction* ok = [UIAlertAction actionWithTitle:NSLocalizedString(@"_ok_", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
            }];
            [alert addAction:ok];
            [self presentViewController:alert animated:YES completion:nil];
            
            // End Select Table View
            [self tableViewSelect:false];

            // reload Datasource
            [self readFileReloadFolder];
            
        } else if (errorCode != 0) {
            
            if (errorCode == kOCErrorServerPathNotFound) {
            
                NSString *fileNamePath = [NSString stringWithFormat:@"%@/%@", metadata.serverUrl, metadata.fileName];
                NSString *fileNameToPath = [NSString stringWithFormat:@"%@/%@", serverUrlTo, metadata.fileName];
            
                [[NCCommunication sharedInstance] moveFileOrFolderWithServerUrlFileNameSource:fileNamePath serverUrlFileNameDestination:fileNameToPath account:appDelegate.activeAccount completionHandler:^(NSString *account, NSInteger errorCode, NSString *errorDescription) {
                    
                    [_hud hideHud];
                    
                    if (errorCode == 0 && [account isEqualToString:appDelegate.activeAccount]) {
                    
                        if (metadata.directory) {
                            [[NCManageDatabase sharedInstance] deleteDirectoryAndSubDirectoryWithServerUrl:[CCUtility stringAppendServerUrl:metadata.serverUrl addFileName:metadata.fileName] account:account];
                        }
                        
                        tableMetadata *metadataNew = [[NCManageDatabase sharedInstance] moveMetadataWithOcId:metadata.ocId serverUrlTo:serverUrlTo];
                        [[NCManageDatabase sharedInstance] moveMediaWithOcId:metadata.ocId serverUrlTo:serverUrlTo];
                        
                        [[NCManageDatabase sharedInstance] clearDateReadWithServerUrl:metadata.serverUrl account:account];
                        [[NCManageDatabase sharedInstance] clearDateReadWithServerUrl:serverUrlTo account:account];
                        
                        if (metadataNew) {
                            NSDictionary* userInfo = @{@"metadata": metadata, @"metadataNew": metadataNew, @"errorCode": @(errorCode), @"errorDescription": @""};
                            [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadName:k_notificationCenter_moveFile object:nil userInfo:userInfo];
                        }
                        
                        // next
                        [_selectedocIdsMetadatas removeObjectForKey:metadata.ocId];
                        
                        if ([_selectedocIdsMetadatas count] > 0) {
                            
                            NSArray *metadatas = [_selectedocIdsMetadatas allValues];
                            
                            [self moveFileOrFolderMetadata:[metadatas objectAtIndex:0] serverUrlTo:serverUrlTo numFile:[_selectedocIdsMetadatas count] ofFile:_numSelectedocIdsMetadatas];
                            
                        } else {
                            
                            // End Select Table View
                            [self tableViewSelect:false];

                            // reload Datasource
                            if (self.searchController.isActive)
                                [self readFolder:metadata.serverUrl];
                            else
                                [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:self.serverUrl ocId:nil action:k_action_NULL];
                        }
                        
                    } else if (errorCode != 0) {
                        
                        [[NCContentPresenter shared] messageNotification:@"_move_" description:errorDescription delay:k_dismissAfterSecond type:messageTypeError errorCode:errorCode];
                        
                        // End Select Table View
                        [self tableViewSelect:false];

                        // reload Datasource
                        if (self.searchController.isActive)
                            [self readFolder:metadata.serverUrl];
                        else
                            [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:metadata.serverUrl ocId:nil action:k_action_NULL];
                        
                        NSDictionary* userInfo = @{@"metadata": metadata, @"metadataNew": metadata, @"errorCode": @(errorCode), @"errorDescription": errorDescription};
                        [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadName:k_notificationCenter_moveFile object:nil userInfo:userInfo];
                        
                    } else {
                        NSLog(@"[LOG] It has been changed user during networking process, error.");
                    }
                }];
                
                [_hud visibleHudTitle:[NSString stringWithFormat:NSLocalizedString(@"_move_file_n_", nil), ofFile - numFile + 1, ofFile] mode:MBProgressHUDModeIndeterminate color:nil];
            } else {
                [[NCContentPresenter shared] messageNotification:@"_error_" description:errorDescription delay:k_dismissAfterSecond type:messageTypeError errorCode:errorCode];
            }
        } else {
            NSLog(@"[LOG] It has been changed user during networking process, error.");
        }
    }];
}

// DELEGATE : Select
- (void)dismissSelectWithServerUrl:(NSString *)serverUrl metadata:(tableMetadata *)metadata type:(NSString *)type
{
    if (serverUrl == nil) {
        [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:self.serverUrl ocId:nil action:k_action_NULL];
    } else {
        
        // E2EE DENIED
        if ([CCUtility isFolderEncrypted:serverUrl account:appDelegate.activeAccount]) {
            
            [[NCContentPresenter shared] messageNotification:@"_move_" description:@"Not possible move files to encrypted directory" delay:k_dismissAfterSecond type:messageTypeInfo errorCode:0];
            return;
        }
        
        if ([_selectedocIdsMetadatas count] > 0) {
            
            _numSelectedocIdsMetadatas = [_selectedocIdsMetadatas count];
            NSArray *metadatas = [_selectedocIdsMetadatas allValues];
            
            [self moveFileOrFolderMetadata:[metadatas objectAtIndex:0] serverUrlTo:serverUrl numFile:[_selectedocIdsMetadatas count] ofFile:_numSelectedocIdsMetadatas];
            
        } else {
            
            _numSelectedocIdsMetadatas = 1;
            [self moveFileOrFolderMetadata:self.metadata serverUrlTo:serverUrl numFile:1 ofFile:_numSelectedocIdsMetadatas];
        }
    }
}

- (void)moveOpenWindow:(NSArray *)indexPaths
{
    if (_isSelectedMode && [_selectedocIdsMetadatas count] == 0)
        return;
    
    UINavigationController *navigationController = [[UIStoryboard storyboardWithName:@"NCSelect" bundle:nil] instantiateInitialViewController];
    NCSelect *viewController = (NCSelect *)navigationController.topViewController;
    
    viewController.delegate = self;
    viewController.hideButtonCreateFolder = false;
    viewController.selectFile = false;
    viewController.includeDirectoryE2EEncryption = false;
    viewController.includeImages = false;
    viewController.type = @"";
    viewController.titleButtonDone = NSLocalizedString(@"_move_", nil);
    viewController.layoutViewSelect = k_layout_view_move;
    
    [navigationController setModalPresentationStyle:UIModalPresentationFullScreen];
    [self presentViewController:navigationController animated:YES completion:nil];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Create folder =====
#pragma --------------------------------------------------------------------------------------------

- (void)createFolder
{
    NSString *serverUrl = [appDelegate getTabBarControllerActiveServerUrl];
    NSString *message;
    UIAlertController *alertController;
    
    if ([serverUrl isEqualToString:[CCUtility getHomeServerUrlActiveUrl:appDelegate.activeUrl]]) {
        message = @"/";
    } else {
        message = [serverUrl lastPathComponent];
    }
    
    alertController = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"_create_folder_on_",nil) message:message preferredStyle:UIAlertControllerStyleAlert];
    
    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        [textField addTarget:self action:@selector(minCharTextFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
        
        textField.autocapitalizationType = UITextAutocapitalizationTypeSentences;
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"_cancel_",nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        NSLog(@"[LOG] Cancel action");
    }];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"_ok_", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        
        UITextField *fileName = alertController.textFields.firstObject;
        
        [[NCNetworking sharedInstance] createFolderWithFileName:fileName.text serverUrl:serverUrl account:appDelegate.activeAccount user:appDelegate.activeUser userID:appDelegate.activeUserID password:appDelegate.activePassword url:appDelegate.activeUrl completion:^(NSInteger errorCode, NSString *errorDescription) { }];
    }];
    
    okAction.enabled = NO;
    
    [alertController addAction:cancelAction];
    [alertController addAction:okAction];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Progress & Task Button =====
#pragma --------------------------------------------------------------------------------------------

- (void)triggerProgressTask:(NSNotification *)notification
{
    if (sectionDataSource.ocIdIndexPath != nil) {
        [[NCMainCommon sharedInstance] triggerProgressTask:notification sectionDataSourceocIdIndexPath:sectionDataSource.ocIdIndexPath tableView:self.tableView viewController:self serverUrlViewController:self.serverUrl];
    }
}

- (void)cancelTaskButton:(id)sender withEvent:(UIEvent *)event
{
    UITouch *touch = [[event allTouches] anyObject];
    CGPoint location = [touch locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];
    
    if ([self indexPathIsValid:indexPath]) {
        
        tableMetadata *metadataSection = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
        
        if (metadataSection) {
            
            tableMetadata *metadata = [[NCManageDatabase sharedInstance] getMetadataWithPredicate:[NSPredicate predicateWithFormat:@"ocId == %@", metadataSection.ocId]];
            if (metadata)
                [[NCMainCommon sharedInstance] cancelTransferMetadata:metadata reloadDatasource:true uploadStatusForcedStart:false];
        }
    }
}

- (void)cancelAllTask:(id)sender
{
    CGPoint location = [sender locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alertController addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"_cancel_all_task_", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [NCUtility.sharedInstance startActivityIndicatorWithView:self.view bottom:0];
        [[NCMainCommon sharedInstance] cancelAllTransfer];
        [NCUtility.sharedInstance stopActivityIndicator];
        [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:nil ocId:nil action:k_action_NULL];
    }]];
    
    [alertController addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"_cancel_", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) { }]];
    
    alertController.popoverPresentationController.sourceView = self.tableView;
    alertController.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
        [alertController.view layoutIfNeeded];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Tap =====
#pragma --------------------------------------------------------------------------------------------

- (void)tapActionComment:(UITapGestureRecognizer *)tapGesture
{
    CGPoint location = [tapGesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];
    
    tableMetadata *metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
    
    if (metadata) {
        [[NCMainCommon sharedInstance] openShareWithViewController:self metadata:metadata indexPage:1];
    }
}

- (void)tapActionShared:(UITapGestureRecognizer *)tapGesture
{
    CGPoint location = [tapGesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];
    
    tableMetadata *metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
    
    if (metadata) {
        [[NCMainCommon sharedInstance] openShareWithViewController:self metadata:metadata indexPage:2];
    }
}

- (void)tapActionConnectionMounted:(UITapGestureRecognizer *)tapGesture
{
    CGPoint location = [tapGesture locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:location];
    
    tableMetadata *metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
    
    if (metadata) {
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Rich Workspace =====
#pragma --------------------------------------------------------------------------------------------

- (void)viewRichWorkspaceTapAction:(UITapGestureRecognizer *)tapGesture
{
    [UIView animateWithDuration:0.5 animations:^{
       
        [self.tableView setContentOffset:CGPointMake(0, heightSearchBar)];
        
    } completion:^(BOOL finished) {
        
        UINavigationController *navigationController = [[UIStoryboard storyboardWithName:@"NCViewerRichWorkspace" bundle:nil] instantiateInitialViewController];
        NCViewerRichWorkspace *viewerRichWorkspace = (NCViewerRichWorkspace *)[navigationController topViewController];
        viewerRichWorkspace.richWorkspaceText = self.richWorkspaceText;
        viewerRichWorkspace.serverUrl = self.serverUrl;
        
        navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
        
        [self presentViewController:navigationController animated:NO completion:NULL];
    }];
}

- (void)createRichWorkspace
{
    NCRichWorkspaceCommon *richWorkspaceCommon = [NCRichWorkspaceCommon new];
    tableMetadata *metadata = [[NCManageDatabase sharedInstance] getMetadataWithPredicate:[NSPredicate predicateWithFormat:@"account == %@ AND serverUrl == %@ AND fileNameView LIKE[c] %@", appDelegate.activeAccount, self.serverUrl, k_fileNameRichWorkspace.lowercaseString]];
    
    if (metadata) {
        [richWorkspaceCommon openViewerNextcloudTextWithServerUrl:self.serverUrl viewController:self];
    } else {
        [richWorkspaceCommon createViewerNextcloudTextWithServerUrl:self.serverUrl viewController:self];
    }
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ==== Menu LOGO ====
#pragma --------------------------------------------------------------------------------------------

- (void)menuLogo:(UIGestureRecognizer *)theGestureRecognizer
{
    
    // Brand
    if ([NCBrandOptions sharedInstance].disable_multiaccount)
        return;
    
    NSArray *listAccount = [[NCManageDatabase sharedInstance] getAccounts];
    
    NSMutableArray *menuArray = [NSMutableArray new];
    
    for (NSString *account in listAccount) {
    
        CCMenuItem *item = [[CCMenuItem alloc] init];
        
        item.title = [account stringByTruncatingToWidth:self.view.bounds.size.width - 100 withFont:[UIFont systemFontOfSize:12.0] atEnd:YES];
        item.argument = account;
        
        tableAccount *tableAccount = [[NCManageDatabase sharedInstance] getAccountWithPredicate:[NSPredicate predicateWithFormat:@"account == %@ ", account]];
        
        NSString *fileNamePath = [NSString stringWithFormat:@"%@/%@-%@.png", [CCUtility getDirectoryUserData], [CCUtility getStringUser:tableAccount.user activeUrl:tableAccount.url], tableAccount.user];
        UIImage *avatar = [UIImage imageWithContentsOfFile:fileNamePath];
        if (avatar) {
            
            avatar = [CCGraphics scaleImage:avatar toSize:CGSizeMake(25, 25) isAspectRation:YES];
            CCAvatar *avatarImageView = [[CCAvatar alloc] initWithImage:avatar borderColor:[UIColor lightGrayColor] borderWidth:0.5];
            CGSize imageSize = avatarImageView.bounds.size;
            UIGraphicsBeginImageContextWithOptions(imageSize, NO, 0);
            CGContextRef context = UIGraphicsGetCurrentContext();
            [avatarImageView.layer renderInContext:context];
            avatar = UIGraphicsGetImageFromCurrentImageContext();
            UIGraphicsEndImageContext();
            
        } else {
            
            avatar = [UIImage imageNamed:@"menuLogoUser"];
        }
        
        item.image = avatar;
        item.target = self;
        
        if ([account isEqualToString:appDelegate.activeAccount]) {
            
            item.action = nil;
            [menuArray insertObject:item atIndex:0];
            
        } else {
        
            item.action = @selector(changeDefaultAccount:);
            [menuArray addObject:item];
        }
    }
    
    // Add + new account
    CCMenuItem *item = [[CCMenuItem alloc] init];
    
    item.title = NSLocalizedString(@"_add_account_", nil);
    item.argument = @"";
    item.image = [CCGraphics changeThemingColorImage:[UIImage imageNamed:@"add"] width:50 height:50 color:NCBrandColor.sharedInstance.textView];
    item.target = self;
    item.action = @selector(addNewAccount:);
    
    [menuArray addObject:item];
    
    OptionalConfiguration options;
    Color backgroundColor;
    
    const CGFloat *componentsBackgroundColor = CGColorGetComponents(NCBrandColor.sharedInstance.backgroundForm.CGColor);
    backgroundColor.R = componentsBackgroundColor[0];
    backgroundColor.G = componentsBackgroundColor[1];
    backgroundColor.B = componentsBackgroundColor[2];
    
    options.arrowSize = 9;
    options.marginXSpacing = 7;
    options.marginYSpacing = 10;
    options.intervalSpacing = 20;
    options.menuCornerRadius = 6.5;
    options.maskToBackground = NO;
    options.shadowOfMenu = YES;
    options.hasSeperatorLine = YES;
    options.seperatorLineHasInsets = YES;
    options.textColor = NCBrandColor.sharedInstance.textView;
    options.menuBackgroundColor = backgroundColor;
    options.separatorColor = NCBrandColor.sharedInstance.separator;
    
    CGRect rect = self.view.frame;
    CGFloat locationY = [theGestureRecognizer locationInView: self.navigationController.navigationBar].y;
    CGFloat safeAreaTop = 0;
    CGFloat offsetY = 35;
    if (@available(iOS 11, *)) {
        safeAreaTop = [UIApplication sharedApplication].delegate.window.safeAreaInsets.top / 2;
    }
    rect.origin.y = locationY + safeAreaTop + offsetY;
    rect.size.height = rect.size.height - locationY - safeAreaTop - offsetY;
    
    [CCMenuAccount setTitleFont:[UIFont systemFontOfSize:12.0]];
    [CCMenuAccount showMenuInView:self.navigationController.view fromRect:rect menuItems:menuArray withOptions:options];    
}

- (void)changeDefaultAccount:(CCMenuItem *)sender
{
    // LOGOUT
    
    tableAccount *tableAccount = [[NCManageDatabase sharedInstance] setAccountActive:[sender argument]];
    if (tableAccount) {
            
        // LOGIN
        [appDelegate settingActiveAccount:tableAccount.account activeUrl:tableAccount.url activeUser:tableAccount.user activeUserID:tableAccount.userID activePassword:[CCUtility getPassword:tableAccount.account]];
    
        // go to home sweet home
        [[NSNotificationCenter defaultCenter] postNotificationOnMainThreadName:k_notificationCenter_initializeMain object:nil userInfo:nil];
    }
}

- (void)addNewAccount:(CCMenuItem *)sender
{
    [appDelegate openLoginView:self selector:k_intro_login openLoginWeb:false];
}

- (void)toggleReMainMenu
{
    [self toggleMenuWithViewController:self.navigationController];
}

- (void)toggleReSelectMenu
{
    [self toggleSelectMenuWithViewController:self.navigationController];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Long Press Recognized Table View / Menu Controller =====
#pragma --------------------------------------------------------------------------------------------

- (void)onLongPressTableView:(UILongPressGestureRecognizer*)recognizer
{
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        
        CGPoint touchPoint = [recognizer locationInView:self.tableView];
        NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:touchPoint];
        NSMutableArray *items = [NSMutableArray new];
        
        if ([self indexPathIsValid:indexPath])
            self.metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
        else
            self.metadata = nil;
        
        [self becomeFirstResponder];
        
        UIMenuController *menuController = [UIMenuController sharedMenuController];
        
        [items addObject:[[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"_copy_file_", nil) action:@selector(copyFile:)]];
        [items addObject:[[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"_copy_files_", nil) action:@selector(copyFiles:)]];
        if ([NCBrandOptions sharedInstance].disable_openin_file == false) {
            [items addObject:[[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"_open_in_", nil) action:@selector(openinFile:)]];
        }
        if ([self.metadata.typeFile isEqualToString: k_metadataTypeFile_document]) {
            [items addObject:[[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"_open_internal_view_", nil) action:@selector(openInternalViewer:)]];
        }
        [items addObject:[[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"_paste_file_", nil) action:@selector(pasteFile:)]];
        [items addObject:[[UIMenuItem alloc] initWithTitle:NSLocalizedString(@"_paste_files_", nil) action:@selector(pasteFiles:)]];

        [menuController setMenuItems:items];
        [menuController setTargetRect:CGRectMake(touchPoint.x, touchPoint.y, 0.0f, 0.0f) inView:self.tableView];
        [menuController setMenuVisible:YES animated:YES];
    }
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender
{
    // For copy file, copy files, Open in ... :
    //
    // NO Directory
    // NO Error Passcode
    // NO In Session mode (download/upload)
    // NO Template
    
    if (@selector(copyFile:) == action || @selector(openinFile:) == action || @selector(openInternalViewer:) == action) {
        
        if (_isSelectedMode == NO && self.metadata && !self.metadata.directory && self.metadata.status == k_metadataStatusNormal) return YES;
        else return NO;
    }
    
    if (@selector(copyFiles:) == action) {
        
        if (_isSelectedMode) {
            
            NSArray *selectedMetadatas = [self getMetadatasFromSelectedRows:[self.tableView indexPathsForSelectedRows]];
            
            for (tableMetadata *metadata in selectedMetadatas) {
                
                if (!metadata.directory && metadata.status == k_metadataStatusNormal)
                    return YES;
            }
        }
        return NO;
    }

    if (@selector(pasteFile:) == action) {
        
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        NSArray *items = [pasteboard items];
        
        if ([items count] == 1) {
            
            // Value : (NSData) ocId
            
            NSDictionary *dic = [items objectAtIndex:0];
            
            NSData *dataocId = [dic objectForKey: k_metadataKeyedUnarchiver];
            NSString *ocId = [NSKeyedUnarchiver unarchiveObjectWithData:dataocId];
            
            if (ocId) {
                tableMetadata *metadata = [[NCManageDatabase sharedInstance] getMetadataWithPredicate:[NSPredicate predicateWithFormat:@"ocId == %@", ocId]];
                if (metadata) {
                    return [CCUtility fileProviderStorageExists:metadata.ocId fileNameView:metadata.fileNameView];
                } else {
                    return NO;
                }
            }
        }
            
        return NO;
    }
    
    if (@selector(pasteFiles:) == action) {
        
        BOOL isValid = NO;
        
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        NSArray *items = [pasteboard items];
        
        if ([items count] <= 1) return NO;
        
        for (NSDictionary *dic in items) {
            
            // Value : (NSData) ocId
            
            NSData *dataocId = [dic objectForKey: k_metadataKeyedUnarchiver];
            NSString *ocId = [NSKeyedUnarchiver unarchiveObjectWithData:dataocId];

            if (ocId) {
                tableMetadata *metadata = [[NCManageDatabase sharedInstance] getMetadataWithPredicate:[NSPredicate predicateWithFormat:@"ocId == %@", ocId]];
                if (metadata) {
                    if ([CCUtility fileProviderStorageExists:metadata.ocId fileNameView:metadata.fileNameView]) {
                        isValid = YES;
                    } else {
                        isValid = NO;
                        break;
                    }
                } else {
                    isValid = NO;
                    break;
                }
            } else {
                isValid = NO;
                break;
            }
        }
        
        return isValid;
    }
    
    return NO;
}

/************************************ COPY ************************************/

- (void)copyFile:(id)sender
{
    // Remove all item
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.items = [[NSArray alloc] init];
    
    if ([CCUtility fileProviderStorageExists:self.metadata.ocId fileNameView:self.metadata.fileNameView]) {
        
        [self copyFileToPasteboard:self.metadata];
        
    } else {
        
        self.metadata.session = k_download_session;
        self.metadata.sessionError = @"";
        self.metadata.sessionSelector = selectorLoadCopy;
        self.metadata.status = k_metadataStatusWaitDownload;
            
        // Add Metadata for Download
        [[NCManageDatabase sharedInstance] addMetadata:self.metadata];
        [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:self.serverUrl ocId:self.metadata.ocId action:k_action_MOD];
        
        [appDelegate startLoadAutoDownloadUpload];
    }
}

- (void)copyFiles:(id)sender
{
    // Remove all item
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.items = [[NSArray alloc] init];
    
    NSArray *selectedMetadatas = [self getMetadatasFromSelectedRows:[self.tableView indexPathsForSelectedRows]];
    
    for (tableMetadata *metadata in selectedMetadatas) {
        
        if ([CCUtility fileProviderStorageExists:metadata.ocId fileNameView:metadata.fileNameView]) {
            
            [self copyFileToPasteboard:metadata];
            
        } else {

            metadata.session = k_download_session;
            metadata.sessionError = @"";
            metadata.sessionSelector = selectorLoadCopy;
            metadata.status = k_metadataStatusWaitDownload;
                
            // Add Metadata for Download
            [[NCManageDatabase sharedInstance] addMetadata:metadata];
            [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:self.serverUrl ocId:metadata.ocId action:k_action_MOD];
            
            [appDelegate startLoadAutoDownloadUpload];
        }
    }
    
    [self tableViewSelect:false];
}

- (void)copyFileToPasteboard:(tableMetadata *)metadata
{
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    NSMutableArray *items = [[NSMutableArray alloc] initWithArray:pasteboard.items];
    
    // Value : (NSData) ocId
    
    NSDictionary *item = [NSDictionary dictionaryWithObjectsAndKeys:[NSKeyedArchiver archivedDataWithRootObject:metadata.ocId], k_metadataKeyedUnarchiver,nil];
    [items addObject:item];
    
    [pasteboard setItems:items];
}

/************************************ OPEN IN ... ******************************/

- (void)openinFile:(id)sender
{
    [[NCMainCommon sharedInstance] downloadOpenWithMetadata:self.metadata selector:selectorOpenIn];
}

/************************************ OPEN INTERNAL VIEWER ... ******************************/
- (void)openInternalViewer:(id)sender
{
    [[NCMainCommon sharedInstance] downloadOpenWithMetadata:self.metadata selector:selectorLoadFileInternalView];
}

/************************************ PASTE ************************************/

- (void)pasteFile:(id)sender
{
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    [self uploadFilePasteArray:[pasteboard items]];
}

- (void)pasteFiles:(id)sender
{
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    [self uploadFilePasteArray:[pasteboard items]];
}

- (void)uploadFilePasteArray:(NSArray *)items
{
    for (NSDictionary *dic in items) {
        
        // Value : (NSData) ocId
        
        NSData *dataocId = [dic objectForKey: k_metadataKeyedUnarchiver];
        NSString *ocId = [NSKeyedUnarchiver unarchiveObjectWithData:dataocId];

        tableMetadata *metadata = [[NCManageDatabase sharedInstance] getMetadataWithPredicate:[NSPredicate predicateWithFormat:@"ocId == %@", ocId]];
        
        if (metadata) {
            
            if ([CCUtility fileProviderStorageExists:metadata.ocId fileNameView:metadata.fileNameView]) {
                
                NSString *fileName = [[NCUtility sharedInstance] createFileName:metadata.fileNameView serverUrl:self.serverUrl account:appDelegate.activeAccount];
                NSString *ocId = [CCUtility createMetadataIDFromAccount:appDelegate.activeAccount serverUrl:self.serverUrl fileNameView:fileName directory:false];
                
                [CCUtility copyFileAtPath:[CCUtility getDirectoryProviderStorageOcId:metadata.ocId fileNameView:metadata.fileNameView] toPath:[CCUtility getDirectoryProviderStorageOcId:ocId fileNameView:fileName]];
                    
                tableMetadata *metadataForUpload = [tableMetadata new];
                        
                metadataForUpload.account = appDelegate.activeAccount;
                metadataForUpload.date = [NSDate new];
                metadataForUpload.ocId = ocId;
                metadataForUpload.fileName = fileName;
                metadataForUpload.fileNameView = fileName;
                metadataForUpload.serverUrl = self.serverUrl;
                metadataForUpload.session = k_upload_session;
                metadataForUpload.sessionSelector = selectorUploadFile;
                metadataForUpload.size = metadata.size;
                metadataForUpload.status = k_metadataStatusWaitUpload;
                            
                // Add Medtadata for upload
                [[NCManageDatabase sharedInstance] addMetadata:metadataForUpload];
                
                [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:self.serverUrl ocId:nil action:k_action_NULL];
            }
        }
    }
    
    [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:self.serverUrl ocId:nil action:k_action_NULL];
    
    [appDelegate startLoadAutoDownloadUpload];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Lock Passcode =====
#pragma --------------------------------------------------------------------------------------------

- (NSUInteger)passcodeViewControllerNumberOfFailedAttempts:(CCBKPasscode *)aViewController
{
    return _failedAttempts;
}

- (NSDate *)passcodeViewControllerLockUntilDate:(CCBKPasscode *)aViewController
{
    return _lockUntilDate;
}

- (void)passcodeViewCloseButtonPressed:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)passcodeViewController:(CCBKPasscode *)aViewController authenticatePasscode:(NSString *)aPasscode resultHandler:(void (^)(BOOL))aResultHandler
{
    if (aViewController.fromType == CCBKPasscodeFromLockScreen || aViewController.fromType == CCBKPasscodeFromLockDirectory || aViewController.fromType == CCBKPasscodeFromDisactivateDirectory ) {
        if ([aPasscode isEqualToString:[CCUtility getBlockCode]]) {
            _lockUntilDate = nil;
            _failedAttempts = 0;
            aResultHandler(YES);
        } else aResultHandler(NO);
    } else aResultHandler(YES);
}

- (void)passcodeViewController:(CCBKPasscode *)aViewController didFinishWithPasscode:(NSString *)aPasscode
{
    [aViewController dismissViewControllerAnimated:YES completion:nil];
    
    switch (aViewController.type) {
            
        case BKPasscodeViewControllerCheckPasscodeType: {
            
            if (aViewController.fromType == CCBKPasscodeFromLockDirectory) {
                
                // possiamo procedere alla prossima directory
                [self performSegueDirectoryWithControlPasscode:false metadata:self.metadata blinkFileNamePath:self.blinkFileNamePath];
                
                // avviamo la sessione Passcode Lock con now
                appDelegate.sessionePasscodeLock = [NSDate date];
            }
            
            // disattivazione lock cartella
            if (aViewController.fromType == CCBKPasscodeFromDisactivateDirectory) {
            
                NSString *lockServerUrl = [CCUtility stringAppendServerUrl:self.metadata.serverUrl addFileName:self.metadata.fileName];
                
                if (![[NCManageDatabase sharedInstance] setDirectoryLockWithServerUrl:lockServerUrl lock:NO account:appDelegate.activeAccount]) {
                
                    [[NCContentPresenter shared] messageNotification:@"_error_" description:@"_error_operation_canc_" delay:k_dismissAfterSecond type:messageTypeError errorCode:k_CCErrorInternalError];
                }
                
                [self tableViewReloadData];
            }
        }
            break;
        default:
            break;
    }
}

- (void)comandoLockPassword
{
    NSString *lockServerUrl = [CCUtility stringAppendServerUrl:self.metadata.serverUrl addFileName:self.metadata.fileName];

    // se non è abilitato il Lock Passcode esci
    if ([[CCUtility getBlockCode] length] == 0) {
        
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"_warning_", nil) message:NSLocalizedString(@"_only_lock_passcode_", nil) preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *goToSettingsAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"_go_to_app_settings_", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self.tabBarController setSelectedIndex:4];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void) {
                NSIndexPath *selectedIndex = [NSIndexPath indexPathForRow:0 inSection:1];
                [appDelegate.activeMore.tableView selectRowAtIndexPath:selectedIndex animated:true scrollPosition: UITableViewScrollPositionNone];
                [appDelegate.activeMore tableView:appDelegate.activeMore.tableView didSelectRowAtIndexPath:selectedIndex];
            });
        }];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"_ok_", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {}];

        [alertController addAction:goToSettingsAction];
        [alertController addAction:okAction];
        [self presentViewController:alertController animated:YES completion:nil];
        return;
    }
    
    // se è richiesta la disattivazione si chiede la password
    tableDirectory *directory = [[NCManageDatabase sharedInstance] getTableDirectoryWithPredicate:[NSPredicate predicateWithFormat:@"account == %@ AND serverUrl == %@", appDelegate.activeAccount, lockServerUrl]];
    
    if (directory.lock) {
        
        CCBKPasscode *viewController = [[CCBKPasscode alloc] initWithNibName:nil bundle:nil];
        viewController.delegate = self;
        viewController.fromType = CCBKPasscodeFromDisactivateDirectory;
        viewController.type = BKPasscodeViewControllerCheckPasscodeType;
        viewController.inputViewTitlePassword = YES;
        
        if ([CCUtility getSimplyBlockCode]) {
            
            viewController.passcodeStyle = BKPasscodeInputViewNumericPasscodeStyle;
            viewController.passcodeInputView.maximumLength = 6;
            
        } else {
            
            viewController.passcodeStyle = BKPasscodeInputViewNormalPasscodeStyle;
            viewController.passcodeInputView.maximumLength = 64;
        }
        
        BKTouchIDManager *touchIDManager = [[BKTouchIDManager alloc] initWithKeychainServiceName:k_serviceShareKeyChain];
        touchIDManager.promptText = NSLocalizedString(@"_scan_fingerprint_", nil);
        viewController.touchIDManager = touchIDManager;

        viewController.title = NSLocalizedString(@"_passcode_protection_", nil);
        viewController.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(passcodeViewCloseButtonPressed:)];
        viewController.navigationItem.leftBarButtonItem.tintColor = [UIColor blackColor];
        
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
        navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:navigationController animated:YES completion:nil];
        
        return;
    }
    
    // ---------------- ACTIVATE PASSWORD
    
    if ([[NCManageDatabase sharedInstance] setDirectoryLockWithServerUrl:lockServerUrl lock:YES account:appDelegate.activeAccount]) {
        
        NSIndexPath *indexPath = [sectionDataSource.ocIdIndexPath objectForKey:self.metadata.ocId];
        if ([self indexPathIsValid:indexPath])
            [self.tableView reloadRowsAtIndexPaths:[NSArray arrayWithObjects:indexPath, nil] withRowAnimation:UITableViewRowAnimationAutomatic];
        
    } else {
        
        [[NCContentPresenter shared] messageNotification:@"_error_" description:@"_error_operation_canc_" delay:k_dismissAfterSecond type:messageTypeError errorCode:k_CCErrorInternalError];
    }
}

#pragma mark -
#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== menu action : Favorite, More, Delete [swipe] =====
#pragma --------------------------------------------------------------------------------------------

- (BOOL)canOpenMenuAction:(tableMetadata *)metadata
{
    if (metadata == nil || _metadataFolder == nil || [[NCManageDatabase sharedInstance] isTableInvalidated:metadata] || metadata.status != k_metadataStatusNormal || [[NCManageDatabase sharedInstance] isTableInvalidated:_metadataFolder])
        return NO;
    
    // E2EE
    if (_metadataFolder.e2eEncrypted && [CCUtility isEndToEndEnabled:appDelegate.activeAccount] == NO)
        return NO;
    
    return YES;
}

- (BOOL)swipeTableCell:(MGSwipeTableCell *)cell canSwipe:(MGSwipeDirection)direction
{
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    tableMetadata *metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
    
    return [self canOpenMenuAction:metadata];
}

-(void)swipeTableCell:(nonnull MGSwipeTableCell *)cell didChangeSwipeState:(MGSwipeState)state gestureIsActive:(BOOL)gestureIsActive
{
}

- (BOOL)swipeTableCell:(MGSwipeTableCell *)cell tappedButtonAtIndex:(NSInteger)index direction:(MGSwipeDirection)direction fromExpansion:(BOOL)fromExpansion
{
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    self.metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
    
    if (direction == MGSwipeDirectionRightToLeft) {
        [self actionDelete:indexPath];
    }
    
    if (direction == MGSwipeDirectionLeftToRight) {
        [[NCNetworking sharedInstance] favoriteMetadata:self.metadata url:appDelegate.activeUrl completion:^(NSInteger errorCode, NSString *errorDescription) { }];
    }
    
    return YES;
}

- (void)actionDelete:(NSIndexPath *)indexPath
{
    tableMetadata *metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
    
    // Directory locked ?
    NSString *lockServerUrl = [CCUtility stringAppendServerUrl:self.metadata.serverUrl addFileName:metadata.fileName];
    
    tableDirectory *directory = [[NCManageDatabase sharedInstance] getTableDirectoryWithPredicate:[NSPredicate predicateWithFormat:@"account == %@ AND serverUrl == %@", appDelegate.activeAccount, lockServerUrl]];
    tableLocalFile *localFile = [[NCManageDatabase sharedInstance] getTableLocalFileWithPredicate:[NSPredicate predicateWithFormat:@"ocId == %@", metadata.ocId]];
    
    if (directory.lock && [[CCUtility getBlockCode] length] && appDelegate.sessionePasscodeLock == nil) {
        
        [[NCContentPresenter shared] messageNotification:@"_error_" description:@"_folder_blocked_" delay:k_dismissAfterSecond type:messageTypeError errorCode:k_CCErrorInternalError];
        return;
    }
    
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alertController addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"_delete_", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self performSelector:@selector(deleteMetadatas) withObject:nil];
    }]];
    
    if (localFile) {
        [alertController addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"_remove_local_file_", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [[NCManageDatabase sharedInstance] deleteLocalFileWithPredicate:[NSPredicate predicateWithFormat:@"ocId == %@", metadata.ocId]];
            [[NSFileManager defaultManager] removeItemAtPath:[CCUtility getDirectoryProviderStorageOcId:metadata.ocId] error:nil];
            [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:self.serverUrl ocId:nil action:k_action_NULL];
        }]];
    }
    
    [alertController addAction: [UIAlertAction actionWithTitle:NSLocalizedString(@"_cancel_", nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
    }]];
    
    alertController.popoverPresentationController.sourceView = self.tableView;
    alertController.popoverPresentationController.sourceRect = [self.tableView rectForRowAtIndexPath:indexPath];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
        [alertController.view layoutIfNeeded];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)actionMore:(UITapGestureRecognizer *)gestureRecognizer
{
    CGPoint touch = [gestureRecognizer locationInView:self.tableView];
    NSIndexPath *indexPath = [self.tableView indexPathForRowAtPoint:touch];
    
    self.metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
    
    [self toggleMoreMenuWithViewController:self.tabBarController indexPath:indexPath metadata:self.metadata metadataFolder:_metadataFolder];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark - ==== Datasource ====
#pragma --------------------------------------------------------------------------------------------

- (void)clearDateReadDataSource:(NSNotification *)notification
{
    _dateReadDataSource = Nil;
    
    [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:self.serverUrl ocId:nil action:k_action_NULL];
}

- (void)reloadDatasource:(NSString *)serverUrl ocId:(NSString *)ocId action:(NSInteger)action
{
    // test
    if (appDelegate.activeAccount.length == 0 || serverUrl.length == 0 || serverUrl == nil || self.view.window == nil)
        return;
    
    // Search Mode
    if (self.searchController.isActive) {
        
        // Create metadatas
        NSMutableArray *metadatas = [NSMutableArray new];
        for (tableMetadata *resultMetadata in _searchResultMetadatas) {
            tableMetadata *metadata = [[NCManageDatabase sharedInstance] getMetadataWithPredicate:[NSPredicate predicateWithFormat:@"ocId == %@", resultMetadata.ocId]];
            if (metadata) {
                [metadatas addObject:metadata];
            }
        }
        
        // [CCUtility getGroupBySettings]
        sectionDataSource = [CCSectionMetadata creataDataSourseSectionMetadata:metadatas listProgressMetadata:nil groupByField:nil filterocId:appDelegate.filterocId filterTypeFileImage:NO filterTypeFileVideo:NO sorted:@"fileName" ascending:NO activeAccount:appDelegate.activeAccount];

        [self tableViewReloadData];
        
        if ([sectionDataSource.allRecordsDataSource count] == 0 && [_searchFileName length] >= k_minCharsSearch) {
            
            _noFilesSearchTitle = NSLocalizedString(@"_search_no_record_found_", nil);
            _noFilesSearchDescription = @"";
        }
        
        if ([sectionDataSource.allRecordsDataSource count] == 0 && [_searchFileName length] < k_minCharsSearch) {
            
            _noFilesSearchTitle = @"";
            _noFilesSearchDescription = NSLocalizedString(@"_search_instruction_", nil);
        }
    
        [self.tableView reloadEmptyDataSet];
        
        return;
    }
    
    // Se non siamo nella dir appropriata esci
    if ([serverUrl isEqualToString:self.serverUrl] == NO || self.serverUrl == nil) {
        return;
    }
    
    // Controllo data lettura Data Source
    tableDirectory *tableDirectory = [[NCManageDatabase sharedInstance] getTableDirectoryWithPredicate:[NSPredicate predicateWithFormat:@"account == %@ AND serverUrl == %@", appDelegate.activeAccount, serverUrl]];
    if (tableDirectory == nil) {
        return;
    }
    
    // Get MetadataFolder
    if ([serverUrl isEqualToString:[CCUtility getHomeServerUrlActiveUrl:appDelegate.activeUrl]])
        _metadataFolder = [[NCManageDatabase sharedInstance] getMetadataWithPredicate:[NSPredicate predicateWithFormat:@"account == %@ AND serverUrl == %@", appDelegate.activeAccount, k_serverUrl_root]];
    else
        _metadataFolder = [[NCManageDatabase sharedInstance] getMetadataWithPredicate:[NSPredicate predicateWithFormat:@"ocId == %@", tableDirectory.ocId]];
    
    // Remove optimization for encrypted directory
    if (_metadataFolder.e2eEncrypted)
        _dateReadDataSource = nil;

    NSDate *dateDateRecordDirectory = tableDirectory.dateReadDirectory;
    
    if ([dateDateRecordDirectory compare:_dateReadDataSource] == NSOrderedDescending || dateDateRecordDirectory == nil || _dateReadDataSource == nil) {
        
        NSLog(@"[LOG] Rebuild Data Source File : %@", _serverUrl);

        _dateReadDataSource = [NSDate date];
    
        // Data Source
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                
            CCSectionDataSourceMetadata *sectionDataSourceTemp = [self queryDatasourceWithReloadData:NO serverUrl:serverUrl];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                sectionDataSource = sectionDataSourceTemp;
                [self tableViewReloadData];
            });
        });
        
    } else {
        
        [self tableViewReloadData];

         NSLog(@"[LOG] [OPTIMIZATION] Rebuild Data Source File : %@ - %@", _serverUrl, _dateReadDataSource);
    }
    
    // BLINK
    if (self.blinkFileNamePath != nil) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void) {
            for (NSString *key in sectionDataSource.allRecordsDataSource) {
                tableMetadata *metadata = [sectionDataSource.allRecordsDataSource objectForKey:key];
                NSString *metadataFileNamePath = [NSString stringWithFormat:@"%@/%@", metadata.serverUrl, metadata.fileName];
                if ([metadataFileNamePath isEqualToString:self.blinkFileNamePath]) {
                    for (NSString *key in sectionDataSource.ocIdIndexPath) {
                        if ([key isEqualToString:metadata.ocId]) {
                            NSIndexPath *indexPath = [sectionDataSource.ocIdIndexPath objectForKey:key];
                            [self.tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionTop animated:NO];
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^(void) {
                                CCCellMain *cell = [self.tableView cellForRowAtIndexPath:indexPath];
                                if (cell) {
                                    self.blinkFileNamePath = nil;
                                    [[NCUtility sharedInstance] blinkWithCell:cell];
                                }
                            });
                        }
                    }
                }
            }
        });
    }
}

- (CCSectionDataSourceMetadata *)queryDatasourceWithReloadData:(BOOL)withReloadData serverUrl:(NSString *)serverUrl
{
    // test
    if (appDelegate.activeAccount.length == 0 || serverUrl == nil) {
        return nil;
    }
    
    // get auto upload folder
    _autoUploadFileName = [[NCManageDatabase sharedInstance] getAccountAutoUploadFileName];
    _autoUploadDirectory = [[NCManageDatabase sharedInstance] getAccountAutoUploadDirectory:appDelegate.activeUrl];
    
    CCSectionDataSourceMetadata *sectionDataSourceTemp = [CCSectionDataSourceMetadata new];

    NSArray *recordsTableMetadata = [[NCManageDatabase sharedInstance] getMetadatasWithPredicate:[NSPredicate predicateWithFormat:@"account == %@ AND serverUrl == %@", appDelegate.activeAccount, serverUrl] sorted:nil ascending:NO];
    
    // [CCUtility getGroupBySettings]
    sectionDataSourceTemp = [CCSectionMetadata creataDataSourseSectionMetadata:recordsTableMetadata listProgressMetadata:nil groupByField:nil filterocId:appDelegate.filterocId filterTypeFileImage:NO filterTypeFileVideo:NO sorted:[CCUtility getOrderSettings] ascending:[CCUtility getAscendingSettings] activeAccount:appDelegate.activeAccount];
    
    if (withReloadData) {
        sectionDataSource = sectionDataSourceTemp;
        [self tableViewReloadData];
    }
    
    return sectionDataSourceTemp;
}

- (NSArray *)getMetadatasFromSelectedRows:(NSArray *)selectedRows
{
    NSMutableArray *metadatas = [[NSMutableArray alloc] init];
    
    if (selectedRows.count > 0) {
    
        for (NSIndexPath *selectionIndex in selectedRows) {
            
            NSString *ocId = [[sectionDataSource.sectionArrayRow objectForKey:[sectionDataSource.sections objectAtIndex:selectionIndex.section]] objectAtIndex:selectionIndex.row];
            tableMetadata *metadata = [sectionDataSource.allRecordsDataSource objectForKey:ocId];

            [metadatas addObject:metadata];
        }
    }
    
    return metadatas;
}

- (NSArray *)getMetadatasFromSectionDataSource:(NSInteger)section
{
    NSInteger totSections =[sectionDataSource.sections count] ;
    
    if ((totSections < (section + 1)) || ((section + 1) > totSections)) {
        return nil;
    }
    
    id valueSection = [sectionDataSource.sections objectAtIndex:section];
    
    return [sectionDataSource.sectionArrayRow objectForKey:valueSection];
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark - ==== Table ==== 
#pragma --------------------------------------------------------------------------------------------

- (void)tableViewToggle
{
    [self tableViewSelect:!_isSelectedMode];
}

- (void)tableViewSelect:(BOOL)toggle
{
    _isSelectedMode = toggle;
    // chiudiamo eventuali swipe aperti
    if (_isSelectedMode)
        [self.tableView setEditing:NO animated:NO];
    
    [self.tableView setAllowsMultipleSelectionDuringEditing:_isSelectedMode];
    [self.tableView setEditing:_isSelectedMode animated:YES];
    
    if (_isSelectedMode)
        [self setUINavigationBarSelected];
    else
        [self setUINavigationBarDefault];
    
    [_selectedocIdsMetadatas removeAllObjects];
    
    [self setTitle];
}

- (void)tableViewReloadData
{
    // store selected cells before relod
    NSArray *indexPaths = [self.tableView indexPathsForSelectedRows];
    
    // reload table view
    [self.tableView reloadData];
    
    // selected cells stored
    for (NSIndexPath *path in indexPaths)
        [self.tableView selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
    
    [self setTableViewHeader];
    [self setTableViewFooter];
    
    if (self.tableView.editing)
        [self setTitle];
    
    [self.tableView reloadEmptyDataSet];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{    
    if (tableView.editing == 1) {
        
        tableMetadata *metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
        
        if (!metadata || [[NCManageDatabase sharedInstance] isTableInvalidated:metadata])
            return NO;
        
        if (metadata == nil || metadata.status != k_metadataStatusNormal)
            return NO;
        else
            return YES;
        
    } else {
        
        [_selectedocIdsMetadatas removeAllObjects];
    }
    
    return YES;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 60;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [[sectionDataSource.sectionArrayRow allKeys] count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [[sectionDataSource.sectionArrayRow objectForKey:[sectionDataSource.sections objectAtIndex:section]] count];
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    NSArray *sections = [sectionDataSource.sectionArrayRow allKeys];
    NSString *sectionTitle = [sections objectAtIndex:section];
    
    if ([sectionTitle isKindOfClass:[NSString class]] && [sectionTitle rangeOfString:@"download"].location != NSNotFound) return 18.f;
    if ([sectionTitle isKindOfClass:[NSString class]] && [sectionTitle rangeOfString:@"upload"].location != NSNotFound) return 18.f;
    
    if ([[CCUtility getGroupBySettings] isEqualToString:@"none"] && [sections count] <= 1) return 0.0f;
    
    return 20.f;
}

-(UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    float shift;
    UIVisualEffectView *visualEffectView;
    
    NSString *titleSection;
    
    if (![self indexPathIsValid:[NSIndexPath indexPathForRow:0 inSection:section]])
        return nil;
    
    if ([[sectionDataSource.sections objectAtIndex:section] isKindOfClass:[NSString class]])
        titleSection = [sectionDataSource.sections objectAtIndex:section];
    
    if ([[sectionDataSource.sections objectAtIndex:section] isKindOfClass:[NSDate class]])
        titleSection = [CCUtility getTitleSectionDate:[sectionDataSource.sections objectAtIndex:section]];
    
    if ([titleSection isEqualToString:@"_none_"]) titleSection = @"";
    else if ([titleSection rangeOfString:@"download"].location != NSNotFound) titleSection = NSLocalizedString(@"_title_section_download_",nil);
    else if ([titleSection rangeOfString:@"upload"].location != NSNotFound) titleSection = NSLocalizedString(@"_title_section_upload_",nil);
    else titleSection = NSLocalizedString(titleSection,nil);
    
    // Format title
    UIVisualEffect *blurEffect;
    blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
    visualEffectView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    visualEffectView.backgroundColor = [NCBrandColor.sharedInstance.brand colorWithAlphaComponent:0.2];
    
    if ([[CCUtility getGroupBySettings] isEqualToString:@"alphabetic"]) {
        
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
            shift = - 35;
        else
            shift =  - 20;
        
    } else shift = - 10;
    
    // Title
    UILabel *titleLabel = [[UILabel alloc]initWithFrame:CGRectMake(10, -12, 0, 44)];
    titleLabel.backgroundColor = [UIColor clearColor];
    titleLabel.textColor = NCBrandColor.sharedInstance.textView;
    titleLabel.font = [UIFont systemFontOfSize:12];
    titleLabel.textAlignment = NSTextAlignmentLeft;
    titleLabel.text = titleSection;
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    [visualEffectView.contentView addSubview:titleLabel];
    
    // Elements
    UILabel *elementLabel= [[UILabel alloc]initWithFrame:CGRectMake(shift, -12, 0, 44)];
    elementLabel.backgroundColor = [UIColor clearColor];
    elementLabel.textColor = NCBrandColor.sharedInstance.textView;
    elementLabel.font = [UIFont systemFontOfSize:12];
    elementLabel.textAlignment = NSTextAlignmentRight;
    elementLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    NSArray *metadatas = [self getMetadatasFromSectionDataSource:section];
    NSUInteger rowsCount = [metadatas count];
    
    if (rowsCount == 0) return nil;
    if (rowsCount == 1) elementLabel.text = [NSString stringWithFormat:@"%lu %@", (unsigned long)rowsCount,  NSLocalizedString(@"_element_",nil)];
    if (rowsCount > 1) elementLabel.text = [NSString stringWithFormat:@"%lu %@", (unsigned long)rowsCount,  NSLocalizedString(@"_elements_",nil)];
    
    [visualEffectView.contentView addSubview:elementLabel];
    
    return visualEffectView;
}

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index
{
    return [sectionDataSource.sections indexOfObject:title];
}

- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView
{
    if ([[CCUtility getGroupBySettings] isEqualToString:@"alphabetic"])
        return [[UILocalizedIndexedCollation currentCollation] sectionIndexTitles];
    else
        return nil;
}

/*
-(void) tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if([indexPath row] == ((NSIndexPath*)[[tableView indexPathsForVisibleRows] lastObject]).row){
        
    }
}
*/

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    tableMetadata *metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
    tableShare *shareCell;
   
    if (metadata == nil || [[NCManageDatabase sharedInstance] isTableInvalidated:metadata] || (_metadataFolder != nil && [[NCManageDatabase sharedInstance] isTableInvalidated:_metadataFolder])) {
        return [CCCellMain new];
    }
    
    for (tableShare *share in appDelegate.shares) {
        if ([share.serverUrl isEqualToString:metadata.serverUrl] && [share.fileName isEqualToString:metadata.fileName]) {
            shareCell = share;
            break;
        }
    }

    UITableViewCell *cell = [[NCMainCommon sharedInstance] cellForRowAtIndexPath:indexPath tableView:tableView metadata:metadata metadataFolder:_metadataFolder serverUrl:self.serverUrl autoUploadFileName:_autoUploadFileName autoUploadDirectory:_autoUploadDirectory tableShare:shareCell];
    
    // NORMAL - > MAIN
    
    if ([cell isKindOfClass:[CCCellMain class]]) {
        
        // Comment tap
        if (metadata.commentsUnread) {
            UITapGestureRecognizer *tapComment = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapActionComment:)];
            [tapComment setNumberOfTapsRequired:1];
            ((CCCellMain *)cell).comment.userInteractionEnabled = YES;
            [((CCCellMain *)cell).comment addGestureRecognizer:tapComment];
        }
        
        // Share add Tap
        UITapGestureRecognizer *tapShare = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapActionShared:)];
        [tapShare setNumberOfTapsRequired:1];
        ((CCCellMain *)cell).viewShared.userInteractionEnabled = YES;
        [((CCCellMain *)cell).viewShared addGestureRecognizer:tapShare];
        
        // More
        if ([self canOpenMenuAction:metadata]) {
            UITapGestureRecognizer *tapMore = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(actionMore:)];
            [tapMore setNumberOfTapsRequired:1];
            ((CCCellMain *)cell).more.userInteractionEnabled = YES;
            [((CCCellMain *)cell).more addGestureRecognizer:tapMore];
        }
        
        // MGSwipeButton
        ((CCCellMain *)cell).delegate = self;

        // LEFT
        ((CCCellMain *)cell).leftButtons = @[[MGSwipeButton buttonWithTitle:@"" icon:self.cellFavouriteImage backgroundColor:NCBrandColor.sharedInstance.yellowFavorite padding:25]];
        
        ((CCCellMain *)cell).leftExpansion.buttonIndex = 0;
        ((CCCellMain *)cell).leftExpansion.fillOnTrigger = NO;
        
        //centerIconOverText
        MGSwipeButton *favoriteButton = (MGSwipeButton *)[((CCCellMain *)cell).leftButtons objectAtIndex:0];
        [favoriteButton centerIconOverText];
        
        // RIGHT
        ((CCCellMain *)cell).rightButtons = @[[MGSwipeButton buttonWithTitle:@"" icon:self.cellTrashImage backgroundColor:[UIColor redColor] padding:25]];
        
        ((CCCellMain *)cell).rightExpansion.buttonIndex = 0;
        ((CCCellMain *)cell).rightExpansion.fillOnTrigger = NO;
        
        //centerIconOverText
        MGSwipeButton *deleteButton = (MGSwipeButton *)[((CCCellMain *)cell).rightButtons objectAtIndex:0];
        [deleteButton centerIconOverText];
    }
    
    // TRANSFER
    
    if ([cell isKindOfClass:[CCCellMainTransfer class]]) {
        
        // gesture Transfer
        [((CCCellMainTransfer *)cell).transferButton.stopButton addTarget:self action:@selector(cancelTaskButton:withEvent:) forControlEvents:UIControlEventTouchUpInside];
        
        UILongPressGestureRecognizer *stopLongGesture = [UILongPressGestureRecognizer new];
        [stopLongGesture addTarget:self action:@selector(cancelAllTask:)];
        [((CCCellMainTransfer *)cell).transferButton.stopButton addGestureRecognizer:stopLongGesture];
    }
    
    return cell;
    
}

- (void)setTableViewHeader
{
    tableCapabilities *capabilities = [[NCManageDatabase sharedInstance] getCapabilitesWithAccount:appDelegate.activeAccount];
  
    if (capabilities.versionMajor < k_nextcloud_version_18_0 || self.richWorkspaceText.length == 0 || self.searchController.isActive) {
                
        [self.tableView.tableHeaderView setFrame:CGRectMake(self.tableView.tableHeaderView.frame.origin.x, self.tableView.tableHeaderView.frame.origin.y, self.tableView.frame.size.width, heightSearchBar)];
        
    } else {
        
        [self.viewRichWorkspace setFrame:CGRectMake(self.tableView.tableHeaderView.frame.origin.x, self.tableView.tableHeaderView.frame.origin.y, self.tableView.frame.size.width, heightRichWorkspace)];
    }
    
    [self.viewRichWorkspace loadWithRichWorkspaceText:self.richWorkspaceText];
    self.searchController.searchBar.frame = CGRectMake(self.searchController.searchBar.frame.origin.x, self.searchController.searchBar.frame.origin.y, self.tableView.frame.size.width, heightSearchBar);
    [self.tableView reloadData];
}

- (void)setTableViewFooter
{
    UIView *footerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 40)];
    [footerView setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin];
    
    UILabel *footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 0, 40)];
    [footerLabel setAutoresizingMask:UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin];
    
    UIFont *appFont = [UIFont systemFontOfSize:12];
    
    footerLabel.font = appFont;
    footerLabel.textColor = [UIColor grayColor];
    footerLabel.backgroundColor = [UIColor clearColor];
    footerLabel.textAlignment = NSTextAlignmentCenter;
    
    NSString *folders;
    NSString *files;
    NSString *footerText;
    
    if (sectionDataSource.directories > 1) {
        folders = [NSString stringWithFormat:@"%ld %@", (long)sectionDataSource.directories, NSLocalizedString(@"_folders_", nil)];
    } else if (sectionDataSource.directories == 1){
        folders = [NSString stringWithFormat:@"%ld %@", (long)sectionDataSource.directories, NSLocalizedString(@"_folder_", nil)];
    } else {
        folders = @"";
    }
    
    if (sectionDataSource.files > 1) {
        files = [NSString stringWithFormat:@"%ld %@ %@", (long)sectionDataSource.files, NSLocalizedString(@"_files_", nil), [CCUtility transformedSize:sectionDataSource.totalSize]];
    } else if (sectionDataSource.files == 1){
        files = [NSString stringWithFormat:@"%ld %@ %@", (long)sectionDataSource.files, NSLocalizedString(@"_file_", nil), [CCUtility transformedSize:sectionDataSource.totalSize]];
    } else {
        files = @"";
    }
    
    if ([folders isEqualToString:@""]) {
        footerText = files;
    } else if ([files isEqualToString:@""]) {
        footerText = folders;
    } else {
        footerText = [NSString stringWithFormat:@"%@, %@", folders, files];
    }
    
    footerLabel.text = footerText;
    
    [footerView addSubview:footerLabel];
    [self.tableView setTableFooterView:footerView];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{    
    CCCellMain *cell = [tableView cellForRowAtIndexPath:indexPath];
    
    // settiamo il record file.
    self.metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
    
    if (!self.metadata)
        return;
    
    // se non può essere selezionata deseleziona
    if ([cell isEditing] == NO)
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    // se siamo in modalità editing impostiamo il titolo dei selezioati e usciamo subito
    if (self.tableView.editing) {
        
        [_selectedocIdsMetadatas setObject:self.metadata forKey:self.metadata.ocId];
        [self setTitle];
        return;
    }
    
    // se è in corso una sessione
    if (self.metadata.status != k_metadataStatusNormal)
        return;
    
    // file
    if (self.metadata.directory == NO) {
        
        // se il file esiste andiamo direttamente al delegato altrimenti carichiamolo
        if ([CCUtility fileProviderStorageExists:self.metadata.ocId fileNameView:self.metadata.fileNameView]) {
            
            [[NCNetworkingMain sharedInstance] downloadFileSuccessFailure:self.metadata.fileName ocId:self.metadata.ocId serverUrl:self.metadata.serverUrl selector:selectorLoadFileView errorMessage:@"" errorCode:0];
            
        } else {
            
            if (_metadataFolder.e2eEncrypted && ![CCUtility isEndToEndEnabled:appDelegate.activeAccount]) {
                
                [[NCContentPresenter shared] messageNotification:@"_info_" description:@"_e2e_goto_settings_for_enable_" delay:k_dismissAfterSecond type:messageTypeInfo errorCode:0];
                
            } else {
            
                if (([self.metadata.typeFile isEqualToString: k_metadataTypeFile_video] || [self.metadata.typeFile isEqualToString: k_metadataTypeFile_audio]) && _metadataFolder.e2eEncrypted == NO) {
                    
                    [self shouldPerformSegue:self.metadata selector:@""];
                    
                } else if ([self.metadata.typeFile isEqualToString: k_metadataTypeFile_document] && [[NCUtility sharedInstance] isDirectEditing:self.metadata] != nil) {
                    
                    if (appDelegate.reachability.isReachable) {
                        [self shouldPerformSegue:self.metadata selector:@""];
                    } else {
                        [[NCContentPresenter shared] messageNotification:@"_info_" description:@"_go_online_" delay:k_dismissAfterSecond type:messageTypeInfo errorCode:0];
                    }
                    
                } else if ([self.metadata.typeFile isEqualToString: k_metadataTypeFile_document] && [[NCUtility sharedInstance] isRichDocument:self.metadata]) {
                    
                    if (appDelegate.reachability.isReachable) {
                        [self shouldPerformSegue:self.metadata selector:@""];
                    } else {
                        [[NCContentPresenter shared] messageNotification:@"_info_" description:@"_go_online_" delay:k_dismissAfterSecond type:messageTypeInfo errorCode:0];
                    }
                    
                } else {
                    
                    if ([self.metadata.typeFile isEqualToString: k_metadataTypeFile_image]) {
                        [self shouldPerformSegue:self.metadata selector:selectorLoadFileView];
                    }
                   
                    self.metadata.session = k_download_session;
                    self.metadata.sessionError = @"";
                    self.metadata.sessionSelector = selectorLoadFileView;
                    self.metadata.status = k_metadataStatusWaitDownload;
                    
                    // Add Metadata for Download
                    [[NCManageDatabase sharedInstance] addMetadata:self.metadata];
                    [[NCMainCommon sharedInstance] reloadDatasourceWithServerUrl:self.serverUrl ocId:self.metadata.ocId action:k_action_MOD];
                    
                    [appDelegate startLoadAutoDownloadUpload];
                }
            }
        }
    }
    
    if (self.metadata.directory) {
        
        [self performSegueDirectoryWithControlPasscode:true metadata:self.metadata blinkFileNamePath:self.blinkFileNamePath];
    }
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(nonnull NSIndexPath *)indexPath
{
    tableMetadata *metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
    
    [_selectedocIdsMetadatas removeObjectForKey:metadata.ocId];
    
    [self setTitle];
}

- (void)didSelectAll
{
    for (int i = 0; i < self.tableView.numberOfSections; i++) {
        for (int j = 0; j < [self.tableView numberOfRowsInSection:i]; j++) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:j inSection:i];
            tableMetadata *metadata = [[NCMainCommon sharedInstance] getMetadataFromSectionDataSourceIndexPath:indexPath sectionDataSource:sectionDataSource];
            [_selectedocIdsMetadatas setObject:metadata forKey:metadata.ocId];
            [self.tableView selectRowAtIndexPath:indexPath animated:NO scrollPosition:UITableViewScrollPositionNone];
        }
    }
    [self setTitle];
}

- (BOOL)indexPathIsValid:(NSIndexPath *)indexPath
{
    if (!indexPath)
        return NO;
    
    NSInteger section = indexPath.section;
    NSInteger row = indexPath.row;
    
    NSInteger lastSectionIndex = [self numberOfSectionsInTableView:self.tableView] - 1;
    
    if (section > lastSectionIndex || lastSectionIndex < 0)
        return NO;
    
    NSInteger rowCount = [self.tableView numberOfRowsInSection:indexPath.section] - 1;
    
    if (rowCount < 0)
        return NO;
    
    return row <= rowCount;
}

#pragma --------------------------------------------------------------------------------------------
#pragma mark ===== Navigation ====
#pragma --------------------------------------------------------------------------------------------

- (void)shouldPerformSegue:(tableMetadata *)metadata selector:(NSString *)selector
{
    // if background return
    if ([[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground) return;
    
    if (self.view.window == NO)
        return;
    
    // Collapsed ma siamo già in detail esci
    if (self.splitViewController.isCollapsed) {
        if (appDelegate.activeDetail.isViewLoaded && appDelegate.activeDetail.view.window) return;
    }
    
    // Metadata for push detail
    self.metadataForPushDetail = metadata;
    self.selectorForPushDetail = selector;
    
    [self performSegueWithIdentifier:@"segueDetail" sender:self];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    tableMetadata *metadata;
    NSMutableArray *photoDataSource = [NSMutableArray new];

    UINavigationController *navigationController = segue.destinationViewController;
    NCDetailViewController *detailViewController = (NCDetailViewController *)navigationController.topViewController;
    
    if ([sender isKindOfClass:[tableMetadata class]]) {
    
        metadata = sender;
        [photoDataSource addObject:sender];
        
    } else {
        
        metadata = self.metadataForPushDetail;
        
        for (NSString *ocId in sectionDataSource.allOcId) {
            tableMetadata *metadata = [sectionDataSource.allRecordsDataSource objectForKey:ocId];
            if ([metadata.typeFile isEqualToString: k_metadataTypeFile_image])
                [photoDataSource addObject:metadata];
        }
    }
    
    detailViewController.metadata = metadata;
    detailViewController.selector = self.selectorForPushDetail;
    
    [detailViewController setTitle:metadata.fileNameView];
}

// can i go to next viewcontroller
- (void)performSegueDirectoryWithControlPasscode:(BOOL)controlPasscode metadata:(tableMetadata *)metadata blinkFileNamePath:(NSString *)blinkFileNamePath
{
    NSString *nomeDir;
    
    if (self.tableView.editing == NO) {
        
        NSString *lockServerUrl = [CCUtility stringAppendServerUrl:metadata.serverUrl addFileName:metadata.fileName];
        
        tableDirectory *directory = [[NCManageDatabase sharedInstance] getTableDirectoryWithPredicate:[NSPredicate predicateWithFormat:@"account == %@ AND serverUrl == %@", metadata.account, lockServerUrl]];
        
        // SE siamo in presenza di una directory bloccata E è attivo il block E la sessione password Lock è senza data ALLORA chiediamo la password per procedere
        if (directory.lock && [[CCUtility getBlockCode] length] && appDelegate.sessionePasscodeLock == nil && controlPasscode) {
            
            CCBKPasscode *viewController = [[CCBKPasscode alloc] initWithNibName:nil bundle:nil];
            viewController.delegate = self;
            viewController.fromType = CCBKPasscodeFromLockDirectory;
            viewController.type = BKPasscodeViewControllerCheckPasscodeType;
            viewController.inputViewTitlePassword = YES;
            
            if ([CCUtility getSimplyBlockCode]) {
                
                viewController.passcodeStyle = BKPasscodeInputViewNumericPasscodeStyle;
                viewController.passcodeInputView.maximumLength = 6;
                
            } else {
                
                viewController.passcodeStyle = BKPasscodeInputViewNormalPasscodeStyle;
                viewController.passcodeInputView.maximumLength = 64;
            }

            BKTouchIDManager *touchIDManager = [[BKTouchIDManager alloc] initWithKeychainServiceName:k_serviceShareKeyChain];
            touchIDManager.promptText = NSLocalizedString(@"_scan_fingerprint_", nil);
            viewController.touchIDManager = touchIDManager;
            
            viewController.title = NSLocalizedString(@"_folder_blocked_", nil);
            viewController.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(passcodeViewCloseButtonPressed:)];
            viewController.navigationItem.leftBarButtonItem.tintColor = [UIColor blackColor];
            
            UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
            navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
            [self presentViewController:navigationController animated:YES completion:nil];
            
            return;
        }
        
        // E2EE Check enable
        if (metadata.e2eEncrypted && [CCUtility isEndToEndEnabled:appDelegate.activeAccount] == NO) {
            
            [[NCContentPresenter shared] messageNotification:@"_info_" description:@"_e2e_goto_settings_for_enable_" delay:k_dismissAfterSecond type:messageTypeInfo errorCode:0];
            return;
        }
        
        nomeDir = metadata.fileName;
        
        NSString *serverUrlPush = [CCUtility stringAppendServerUrl:metadata.serverUrl addFileName:nomeDir];
    
        CCMain *viewController = [appDelegate.listMainVC objectForKey:serverUrlPush];
        
        if (!viewController) {
            
            viewController = [[UIStoryboard storyboardWithName:@"Main" bundle:nil] instantiateViewControllerWithIdentifier:@"CCMain"];
            
            viewController.serverUrl = serverUrlPush;
            viewController.titleMain = metadata.fileName;
            viewController.blinkFileNamePath = blinkFileNamePath;
            
            // save self
            [appDelegate.listMainVC setObject:viewController forKey:serverUrlPush];
            
            [self.navigationController pushViewController:viewController animated:YES];
        
        } else {
           
            if (viewController.isViewLoaded) {
                
                viewController.titleMain = metadata.fileName;
                viewController.blinkFileNamePath = blinkFileNamePath;
                
                // Fix : Application tried to present modally an active controller
                if ([self.navigationController isBeingPresented]) {
                    // being presented
                } else if ([self.navigationController isMovingToParentViewController]) {
                    // being pushed
                } else {
                    [self.navigationController pushViewController:viewController animated:YES];
                }
            }
        }
    }
}

@end
