//
//  RootViewController.m
//  AppSales
//
//  Created by Ole Zorn on 30.06.11.
//  Copyright 2011 omz:software. All rights reserved.
//

#import "AccountsViewController.h"
#import "SalesViewController.h"
#import "SSKeychain.h"
#import "ASAccount.h"
#import "Report.h"
#import "Product.h"
#import "CurrencyManager.h"
#import "ReportDownloadCoordinator.h"
#import "MBProgressHUD.h"
#import "ReportImportOperation.h"
#import "BadgedCell.h"
#import "AboutViewController.h"
#import "AccountStatusView.h"
#import "KKPasscodeLock.h"
#import "ZipFile.h"
#import "ZipWriteStream.h"

#define kAddNewAccountEditorIdentifier		@"AddNewAccountEditorIdentifier"
#define kEditAccountEditorIdentifier		@"EditAccountEditorIdentifier"
#define kSettingsEditorIdentifier			@"SettingsEditorIdentifier"
#define kUpdateExchangeRatesButton			@"UpdateExchangeRatesButton"
#define kPasscodeLockButton					@"PasscodeLockButton"
#define kImportReportsButton				@"ImportReportsButton"
#define kExportReportsButton				@"ExportReportsButton"
#define kDownloadBoxcarButton				@"DownloadBoxcarButton"
#define kAddToBoxcarButton					@"AddToBoxcarButton"
#define	kDeleteAccountButton				@"DeleteAccount"
#define kAlertTagConfirmImport				1
#define kAlertTagExportCompleted			2
#define kAlertTagConfirmDelete				3
#define kAccountTitle						@"title"
#define kKeychainServiceIdentifier			@"iTunesConnect"


@implementation AccountsViewController

@synthesize managedObjectContext, accounts, selectedAccount, refreshButtonItem, delegate, exportedReportsZipPath, documentInteractionController;

- (void)viewDidLoad
{
	[super viewDidLoad];
	
	self.refreshButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(downloadReports:)] autorelease];
	UIBarButtonItem *settingsButtonItem = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Settings", nil) style:UIBarButtonItemStyleBordered target:self action:@selector(showSettings)] autorelease];
	UIBarButtonItem *flexSpace = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil] autorelease];
	UIButton *infoButton = [UIButton buttonWithType:UIButtonTypeInfoLight];
	[infoButton addTarget:self action:@selector(showInfo:) forControlEvents:UIControlEventTouchUpInside];
	UIBarButtonItem *infoButtonItem = [[[UIBarButtonItem alloc] initWithCustomView:infoButton] autorelease];
	
	self.toolbarItems = [NSArray arrayWithObjects:infoButtonItem, flexSpace, settingsButtonItem, nil];
	self.navigationItem.rightBarButtonItem = refreshButtonItem;
	
	self.title = NSLocalizedString(@"AppSales", nil);
	self.navigationItem.backBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain target:nil action:nil] autorelease];
	
	UIBarButtonItem *addButton = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addNewAccount)] autorelease];
	self.navigationItem.leftBarButtonItem = addButton;
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(contextDidChange:) name:NSManagedObjectContextObjectsDidChangeNotification object:[self managedObjectContext]];
	
	[[ReportDownloadCoordinator sharedReportDownloadCoordinator] addObserver:self forKeyPath:@"isBusy" options:NSKeyValueObservingOptionNew context:nil];
	
	[self reloadAccounts];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ([keyPath isEqualToString:@"isBusy"]) {
		dispatch_async(dispatch_get_main_queue(), ^ {
			self.refreshButtonItem.enabled = ![[ReportDownloadCoordinator sharedReportDownloadCoordinator] isBusy];
		});
	}
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];
	if (![[ReportDownloadCoordinator sharedReportDownloadCoordinator] isBusy] && [self.accounts count] == 0) {
		[self addNewAccount];
	}
}

- (void)contextDidChange:(NSNotification *)notification
{
	[NSObject cancelPreviousPerformRequestsWithTarget:self];
	[self.tableView performSelector:@selector(reloadData) withObject:nil afterDelay:0.1];
}

- (void)reloadAccounts
{
	NSFetchRequest *accountsFetchRequest = [[[NSFetchRequest alloc] init] autorelease];
	[accountsFetchRequest setEntity:[NSEntityDescription entityForName:@"Account" inManagedObjectContext:self.managedObjectContext]];
	[accountsFetchRequest setSortDescriptors:[NSArray arrayWithObjects:[[[NSSortDescriptor alloc] initWithKey:@"title" ascending:YES] autorelease], [[[NSSortDescriptor alloc] initWithKey:@"username" ascending:YES] autorelease], nil]];
	self.accounts = [self.managedObjectContext executeFetchRequest:accountsFetchRequest error:NULL];
	
	[self.tableView reloadData];
}

- (void)deleteAllAccountPasswords {
	[self.accounts enumerateObjectsUsingBlock:^(ASAccount * _Nonnull account, NSUInteger idx, BOOL * _Nonnull stop) {
		NSLog(@"deleting %@ pass", account.username);
		[account deletePassword];
	}];
	[self saveContext];
}

- (void)downloadReports:(id)sender
{
	for (ASAccount *account in self.accounts) {
		if (account.token && account.token.length > 0) { //Only download reports for accounts with login
			if (!account.vendorID || account.vendorID.length == 0) {
				[[[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Vendor ID Missing", nil) 
											 message:[NSString stringWithFormat:NSLocalizedString(@"You have not entered a vendor ID for the account with token \"%@\". Please go to the account's settings and fill in the missing information.", nil), [account token]]
											delegate:nil 
								   cancelButtonTitle:NSLocalizedString(@"OK", nil) 
								   otherButtonTitles:nil] autorelease] show];
			} else {
				[[ReportDownloadCoordinator sharedReportDownloadCoordinator] downloadReportsForAccount:account];
			}
		}
	}
}

- (void)showInfo:(id)sender
{
	AboutViewController *aboutViewController = [[[AboutViewController alloc] initWithNibName:nil bundle:nil] autorelease];
	UINavigationController *aboutNavController = [[[UINavigationController alloc] initWithRootViewController:aboutViewController] autorelease];
	
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
		aboutNavController.modalPresentationStyle = UIModalPresentationFormSheet;
	}
	[self presentViewController:aboutNavController animated:YES completion:nil];
}


- (void)viewDidUnload
{
    [super viewDidUnload];
}


#pragma mark - Table view

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) return nil;
	
	if ([self.accounts count] == 0) {
		return nil;
	}
	ASAccount *account = [self.accounts objectAtIndex:section];
	NSString *title = account.title;
	if (!title || [title isEqualToString:@""]) {
		title = account.username;
	}
	return title;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) return 1;
	
	if ([self.accounts count] == 0) {
		return 1;
	}
	return [self.accounts count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) return self.accounts.count;
	
	if ([self.accounts count] == 0) {
		return 0;
	}
	return 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
	static NSString *cellIdentifier = @"Cell";
	BadgedCell *cell = (BadgedCell *)[tableView dequeueReusableCellWithIdentifier:cellIdentifier];
	if (cell == nil) {
		cell = [[[BadgedCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellIdentifier] autorelease];
	}
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
		cell.textLabel.text = [[self.accounts objectAtIndex:indexPath.row] displayName];
		cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
		return cell;
	}
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	if (indexPath.row == 0) {
		NSInteger badge = [[[self.accounts objectAtIndex:indexPath.section] reportsBadge] integerValue];
		cell.textLabel.text = NSLocalizedString(@"Sales and Trends", nil);
		cell.badgeCount = badge;
		cell.imageView.image = [UIImage imageNamed:@"Sales.png"];
	} else if (indexPath.row == 1) {
		cell.textLabel.text = NSLocalizedString(@"Account", nil);
		cell.imageView.image = [UIImage imageNamed:@"Account.png"];
		cell.badgeCount = 0;
	}
	return cell;
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath
{
	//iPad only
	ASAccount *account = [self.accounts objectAtIndex:indexPath.row];
	[self editAccount:account];
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) return nil;
	
	if ([self.accounts count] == 0) {
		return nil;
	}
	ASAccount *account = [self.accounts objectAtIndex:section];
	return [[[AccountStatusView alloc] initWithFrame:CGRectMake(0, 0, 320, 26) account:account] autorelease];
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
	return 26.0;
}


- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return 44.0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
		if (self.delegate) {
			ASAccount *account = [self.accounts objectAtIndex:indexPath.row];
			[self.delegate accountsViewController:self didSelectAccount:account];
		}
		return;
	}
	ASAccount *account = [self.accounts objectAtIndex:indexPath.section];
	if (indexPath.row == 0) {
		SalesViewController *salesViewController = [[[SalesViewController alloc] initWithAccount:account] autorelease];
		[self.navigationController pushViewController:salesViewController animated:YES];
	} else if (indexPath.row == 1) {
		[self editAccount:account];
	}
}

#pragma mark -

- (void)deleteAccount:(NSManagedObject *)account
{
	if (account) {
		NSManagedObjectContext *context = self.managedObjectContext;
		[context deleteObject:account];
		[MBProgressHUD hideHUDForView:self.navigationController.view animated:YES];
		[self reloadAccounts];
	}
}

- (void)addNewAccount
{
	FieldSpecifier *titleField = [FieldSpecifier textFieldWithKey:kAccountTitle title:@"Description" defaultValue:@""];
	titleField.placeholder = NSLocalizedString(@"optional", nil);
	FieldSectionSpecifier *titleSection = [FieldSectionSpecifier sectionWithFields:[NSArray arrayWithObject:titleField] title:nil description:nil];
	
	FieldSpecifier *tokenField = [FieldSpecifier textFieldWithKey:kAccountToken title:NSLocalizedString(@"Token", nil) defaultValue:@""];
	FieldSpecifier *vendorIDField = [FieldSpecifier numericFieldWithKey:kAccountVendorID title:NSLocalizedString(@"Vendor ID", nil) defaultValue:@""];
	vendorIDField.placeholder = @"8XXXXXXX";
//	FieldSpecifier *selectVendorIDButtonField = [FieldSpecifier buttonFieldWithKey:@"SelectVendorIDButton" title:NSLocalizedString(@"Auto-Fill Vendor ID...", nil)];
	
	FieldSectionSpecifier *loginSection = [FieldSectionSpecifier sectionWithFields:[NSArray arrayWithObjects:tokenField, vendorIDField, nil]
																			 title:NSLocalizedString(@"iTunes Connect Login", nil) 
																	   description:NSLocalizedString(@"You can import reports via iTunes File Sharing without entering your login.", nil)];
	
	NSArray *sections = [NSArray arrayWithObjects:titleSection, loginSection, nil];
	FieldEditorViewController *addAccountViewController = [[[FieldEditorViewController alloc] initWithFieldSections:sections title:NSLocalizedString(@"New Account",nil)] autorelease];
	addAccountViewController.cancelButtonTitle = NSLocalizedString(@"Cancel", nil);
	addAccountViewController.doneButtonTitle = NSLocalizedString(@"Done", nil);
	addAccountViewController.delegate = self;
	addAccountViewController.editorIdentifier = kAddNewAccountEditorIdentifier;
	UINavigationController *navigationController = [[[UINavigationController alloc] initWithRootViewController:addAccountViewController] autorelease];
	
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
		navigationController.modalPresentationStyle = UIModalPresentationFormSheet;
		
	}
	[self presentViewController:navigationController animated:YES completion:nil];
}

- (void)editAccount:(ASAccount *)account
{
	self.selectedAccount = account;
	NSString *token = account.token;
	NSString *title = account.title;
	NSString *vendorID = account.vendorID;
	
	FieldSpecifier *titleField = [FieldSpecifier textFieldWithKey:kAccountTitle title:@"Description" defaultValue:title];
	titleField.placeholder = NSLocalizedString(@"optional", nil);
	
	FieldSpecifier *tokenField = [FieldSpecifier textFieldWithKey:kAccountToken title:NSLocalizedString(@"Token", nil) defaultValue:token];
	FieldSpecifier *vendorIDField = [FieldSpecifier numericFieldWithKey:kAccountVendorID title:NSLocalizedString(@"Vendor ID", nil) defaultValue:vendorID];
//	FieldSpecifier *selectVendorIDButtonField = [FieldSpecifier buttonFieldWithKey:@"SelectVendorIDButton" title:NSLocalizedString(@"Auto-Fill Vendor ID...", nil)];
	
	vendorIDField.placeholder = @"8XXXXXXX";
	FieldSectionSpecifier *loginSection = [FieldSectionSpecifier sectionWithFields:[NSArray arrayWithObjects:tokenField, vendorIDField, nil]
																			 title:NSLocalizedString(@"iTunes Connect Login", nil) 
																	   description:nil];
	FieldSpecifier *loginSubsectionField = [FieldSpecifier subsectionFieldWithSection:loginSection key:@"iTunesConnect"];
	FieldSectionSpecifier *titleSection = [FieldSectionSpecifier sectionWithFields:[NSArray arrayWithObjects:titleField, loginSubsectionField, nil] title:nil description:nil];
	
	FieldSpecifier *importButtonField = [FieldSpecifier buttonFieldWithKey:kImportReportsButton title:NSLocalizedString(@"Import Reports...", nil)];
	FieldSpecifier *exportButtonField = [FieldSpecifier buttonFieldWithKey:kExportReportsButton title:NSLocalizedString(@"Export Reports...", nil)];
	FieldSectionSpecifier *importExportSection = [FieldSectionSpecifier sectionWithFields:[NSArray arrayWithObjects:importButtonField, exportButtonField, nil] 
																					title:nil 
																			  description:nil /*NSLocalizedString(@"Use iTunes file sharing to import report files from your computer.",nil)*/];
	
	NSMutableArray *productFields = [NSMutableArray array];
	NSArray *allProducts = [[account.products allObjects] sortedArrayUsingDescriptors:[NSArray arrayWithObject:[[[NSSortDescriptor alloc] initWithKey:@"productID" ascending:NO] autorelease]]];
	
	for (Product *product in allProducts) {
		FieldSpecifier *productNameField = [FieldSpecifier textFieldWithKey:[NSString stringWithFormat:@"product.name.%@", product.productID] title:NSLocalizedString(@"Name", nil) defaultValue:[product displayName]];
		FieldSpecifier *hideProductField = [FieldSpecifier switchFieldWithKey:[NSString stringWithFormat:@"product.hidden.%@", product.productID] title:NSLocalizedString(@"Hide in Dashboard", nil) defaultValue:[product.hidden boolValue]];
		FieldSectionSpecifier *productSection = [FieldSectionSpecifier sectionWithFields:[NSArray arrayWithObjects:productNameField, hideProductField, nil] title:nil description:nil];
		FieldSpecifier *showInAppStoreField = [FieldSpecifier buttonFieldWithKey:[NSString stringWithFormat:@"product.appstore.%@", product.productID] title:NSLocalizedString(@"Show in App Store...", nil)];
		NSString *productFooter = [NSString stringWithFormat:@"Current version: %@\nApple ID: %@", ((product.currentVersion) ? product.currentVersion : @"N/A"), product.productID];
		FieldSectionSpecifier *showInAppStoreSection = [FieldSectionSpecifier sectionWithFields:[NSArray arrayWithObject:showInAppStoreField] title:nil description:productFooter];
		FieldSpecifier *productSectionField = [FieldSpecifier subsectionFieldWithSections:[NSArray arrayWithObjects:productSection, showInAppStoreSection, nil] key:[NSString stringWithFormat:@"product.section.%@", product.productID] title:[product defaultDisplayName]];
		[productFields addObject:productSectionField];
	}
	FieldSectionSpecifier *productsSection = [FieldSectionSpecifier sectionWithFields:productFields title:NSLocalizedString(@"Manage Apps", nil) description:nil];
	FieldSpecifier *manageProductsSectionField = [FieldSpecifier subsectionFieldWithSection:productsSection key:@"ManageProducts"];
	FieldSectionSpecifier *manageProductsSection = [FieldSectionSpecifier sectionWithFields:[NSArray arrayWithObject:manageProductsSectionField] title:nil description:nil];
	if ([allProducts count] == 0) {
		productsSection.description = NSLocalizedString(@"This account does not contain any apps yet. Import or download reports first.", nil);
	}
	
	FieldSpecifier *deleteAccountButtonField = [FieldSpecifier buttonFieldWithKey:kDeleteAccountButton title:NSLocalizedString(@"Delete Account...", nil)];
	FieldSectionSpecifier *deleteAccountSection = [FieldSectionSpecifier sectionWithFields:[NSArray arrayWithObject:deleteAccountButtonField] title:nil description:nil];
	
	NSArray *sections = [NSArray arrayWithObjects:titleSection, importExportSection, manageProductsSection, deleteAccountSection, nil];
	FieldEditorViewController *editAccountViewController = [[[FieldEditorViewController alloc] initWithFieldSections:sections title:NSLocalizedString(@"Account Details",nil)] autorelease];
	editAccountViewController.doneButtonTitle = nil;
	editAccountViewController.delegate = self;
	editAccountViewController.editorIdentifier = kEditAccountEditorIdentifier;
	editAccountViewController.context = account;
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
		editAccountViewController.hidesBottomBarWhenPushed = YES;
	}
	
	editAccountViewController.preferredContentSize = CGSizeMake(320, 480);
	
	[self.navigationController pushViewController:editAccountViewController animated:YES];
}

- (void)showSettings
{
	// main section
	passcodeLockField = [FieldSpecifier buttonFieldWithKey:kPasscodeLockButton title:NSLocalizedString(@"Passcode Lock", nil)];
	if ([[KKPasscodeLock sharedLock] isPasscodeRequired]) {
		passcodeLockField.defaultValue = @"On";
	} else {
		passcodeLockField.defaultValue = @"Off";
	}
	
	NSString *baseCurrency = [[CurrencyManager sharedManager] baseCurrency];
	NSArray *availableCurrencies = [[CurrencyManager sharedManager] availableCurrencies];
	NSMutableArray *currencyFields = [NSMutableArray array];
	for (NSString *currency in availableCurrencies) {
		FieldSpecifier *currencyField = [FieldSpecifier checkFieldWithKey:[NSString stringWithFormat:@"currency.%@", currency] title:currency defaultValue:[baseCurrency isEqualToString:currency]];
		[currencyFields addObject:currencyField];
	}
	FieldSectionSpecifier *currencySection = [FieldSectionSpecifier sectionWithFields:currencyFields
																				title:NSLocalizedString(@"Currency", nil)
																		  description:nil];
	currencySection.exclusiveSelection = YES;
	FieldSpecifier *currencySectionField = [FieldSpecifier subsectionFieldWithSection:currencySection key:@"currency"];
	FieldSpecifier *updateExchangeRatesButtonField = [FieldSpecifier buttonFieldWithKey:kUpdateExchangeRatesButton title:NSLocalizedString(@"Update Exchange Rates Now", nil)];	
	FieldSectionSpecifier *mainSection = [FieldSectionSpecifier sectionWithFields:[NSArray arrayWithObjects:passcodeLockField, currencySectionField, updateExchangeRatesButtonField, nil] 
																			title:NSLocalizedString(@"General", nil) 
																	  description:NSLocalizedString(@"Exchange rates will automatically be refreshed periodically.", nil)];


  
	// products section
	NSString* productSortByValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"ProductSortby"];
	FieldSpecifier *productSortingByProductIdField = [FieldSpecifier checkFieldWithKey:@"sortby.productId" title:@"Product ID" 
																			defaultValue:[productSortByValue isEqualToString:@"productId"]];
	FieldSpecifier *productSortingByColorField = [FieldSpecifier checkFieldWithKey:@"sortby.color" title:@"Color" 
																		defaultValue:[productSortByValue isEqualToString:@"color"]];
	NSMutableArray *productSortingFields = [NSMutableArray arrayWithObjects:productSortingByProductIdField, productSortingByColorField, nil];


	FieldSectionSpecifier *productSortingSection = [FieldSectionSpecifier sectionWithFields:productSortingFields
																				  title:NSLocalizedString(@"Sort By", nil)
																			description:nil];
	productSortingSection.exclusiveSelection = YES;
	FieldSpecifier *productsSectionField = [FieldSpecifier subsectionFieldWithSection:productSortingSection key:@"sortby"];
	FieldSectionSpecifier *productsSection = [FieldSectionSpecifier sectionWithFields:[NSArray arrayWithObjects:productsSectionField, nil] 
																				  title:NSLocalizedString(@"Products", nil) 
																			description:NSLocalizedString(@"", nil)];
	
	// push section
	FieldSpecifier *downloadBoxcarButtonField = [FieldSpecifier buttonFieldWithKey:kDownloadBoxcarButton title:NSLocalizedString(@"Install Boxcar...", nil)];
	FieldSpecifier *addToBoxcarButtonField = [FieldSpecifier buttonFieldWithKey:kAddToBoxcarButton title:NSLocalizedString(@"Add AppSales to Boxcar...", nil)];
	FieldSectionSpecifier *pushSection = [FieldSectionSpecifier sectionWithFields:[NSArray arrayWithObjects:downloadBoxcarButtonField, addToBoxcarButtonField, nil] 
																			title:NSLocalizedString(@"Push Notifications", nil) 
																	  description:NSLocalizedString(@"To receive push notifications when new sales reports are available you have to install the free Boxcar app.", nil)];
	FieldSpecifier *pushSectionField = [FieldSpecifier subsectionFieldWithSection:pushSection key:@"PushSection"];
	FieldSectionSpecifier *pushSectionFieldSection = [FieldSectionSpecifier sectionWithFields:[NSArray arrayWithObject:pushSectionField] title:NSLocalizedString(@"Push Notifications", nil) description:nil];
		  
	NSArray *sections = [NSArray arrayWithObjects:mainSection, productsSection, pushSectionFieldSection, nil];
	settingsViewController = [[[FieldEditorViewController alloc] initWithFieldSections:sections title:NSLocalizedString(@"Settings",nil)] autorelease];
	settingsViewController.doneButtonTitle = NSLocalizedString(@"Done", nil);
	settingsViewController.delegate = self;
	settingsViewController.editorIdentifier = kSettingsEditorIdentifier;
	
	settingsNavController = [[[UINavigationController alloc] initWithRootViewController:settingsViewController] autorelease];
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
		settingsNavController.modalPresentationStyle = UIModalPresentationFormSheet;
	}
	[self presentViewController:settingsNavController animated:YES completion:nil];
}

- (void)fieldEditor:(FieldEditorViewController *)editor didFinishEditingWithValues:(NSDictionary *)returnValues
{
	if ([editor.editorIdentifier isEqualToString:kAddNewAccountEditorIdentifier] || [editor.editorIdentifier isEqualToString:kEditAccountEditorIdentifier]) {
		NSString *token = [returnValues objectForKey:kAccountToken];
		NSString *vendorID = [returnValues objectForKey:kAccountVendorID];
		NSString *title = [returnValues objectForKey:kAccountTitle];
		if (!title || [title isEqualToString:@""]) {
			[[[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Missing Information", nil) message:NSLocalizedString(@"You need to enter at least a description.\n\nIf you want to download reports from iTunes Connect, you need to enter an access token, otherwise you can just enter a description.", nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", nil) otherButtonTitles:nil] autorelease] show];
			return;
		}
		if ([editor.editorIdentifier isEqualToString:kAddNewAccountEditorIdentifier]) {
			if (token && token.length > 0 && (!vendorID || vendorID.length == 0)) {
				[[[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Missing Information", nil) message:NSLocalizedString(@"You need to enter a vendor ID. If you don't know your vendor ID, tap \"Auto-Fill Vendor ID\".", nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", nil) otherButtonTitles:nil] autorelease] show];
				return;
			}
			ASAccount *account = (ASAccount *)[NSEntityDescription insertNewObjectForEntityForName:@"Account" inManagedObjectContext:self.managedObjectContext];
			account.title = title;
			account.vendorID = vendorID;
			account.sortIndex = [NSNumber numberWithLong:time(NULL)];
			[account setToken:token];
		}
		else if ([editor.editorIdentifier isEqualToString:kEditAccountEditorIdentifier]) {
			ASAccount *account = (ASAccount *)editor.context;
			[account deleteToken];
			account.title = title;
			account.vendorID = vendorID;
			[account setToken:token];
			
			NSMutableDictionary *productsByID = [NSMutableDictionary dictionary];
			for (Product *product in self.selectedAccount.products) {
				[productsByID setObject:product forKey:product.productID];
			}
			for (NSString *key in [returnValues allKeys]) {
				if ([key hasPrefix:@"product.name."]) {
					NSString *productID = [key substringFromIndex:[@"product.name." length]];
					Product *product = [productsByID objectForKey:productID];
					NSString *newName = [returnValues objectForKey:key];
					if (![[product displayName] isEqualToString:newName]) {
						product.customName = newName;
					}
				} else if ([key hasPrefix:@"product.hidden."]) {
					NSString *productID = [key substringFromIndex:[@"product.hidden." length]];
					Product *product = [productsByID objectForKey:productID];
					product.hidden = [returnValues objectForKey:key];
				}
			}
		}
		[self saveContext];
		if ([editor.editorIdentifier isEqualToString:kAddNewAccountEditorIdentifier]) {
			[editor dismissViewControllerAnimated:YES completion:nil];
		}
		self.selectedAccount = nil;
	} else if ([editor.editorIdentifier isEqualToString:kSettingsEditorIdentifier]) {
		for (NSString *key in [returnValues allKeys]) {
			if ([key hasPrefix:@"currency."]) {
				if ([[returnValues objectForKey:key] boolValue]) {
					[[CurrencyManager sharedManager] setBaseCurrency:[[key componentsSeparatedByString:@"."] lastObject]];
				}
			}
			if ([key hasPrefix:@"sortby."]) {
				if ([[returnValues objectForKey:key] boolValue]) {
					[[NSUserDefaults standardUserDefaults] setObject:[[key componentsSeparatedByString:@"."] lastObject] forKey:@"ProductSortby"];
				}
			}
		}
		[self dismissViewControllerAnimated:YES completion:nil];
		
		[[NSNotificationCenter defaultCenter] postNotificationName:ASViewSettingsDidChangeNotification object:nil];
	}
	[self reloadAccounts];
}

- (void)fieldEditor:(FieldEditorViewController *)editor pressedButtonWithKey:(NSString *)key
{
	
  if ([key isEqualToString:kPasscodeLockButton]) {
    KKPasscodeSettingsViewController *vc = [[[KKPasscodeSettingsViewController alloc] initWithStyle:UITableViewStyleGrouped] autorelease];
    vc.delegate = self;
    [settingsNavController pushViewController:vc animated:YES];
     } else if ([key isEqualToString:kUpdateExchangeRatesButton]) {
		[[CurrencyManager sharedManager] forceRefresh];
	} else if ([key isEqualToString:kImportReportsButton]) {
		ASAccount *account = (ASAccount *)editor.context;
		if (account.isDownloadingReports) {
			[[[[UIAlertView alloc] initWithTitle:nil message:NSLocalizedString(@"AppSales is already importing reports for this account. Please wait until the current import has finished.", nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", nil) otherButtonTitles:nil] autorelease] show];
		} else {
			BOOL canStartImport = [ReportImportOperation filesAvailableToImport];
			if (!canStartImport) {
				[[[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"No Files Found", nil) message:NSLocalizedString(@"The Documents directory does not contain any .txt files. Please use iTunes File Sharing to transfer report files to your device.", nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", nil) otherButtonTitles:nil] autorelease] show];
			} else {
				UIAlertView *confirmImportAlert = [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Begin Import?", nil) 
																			  message:NSLocalizedString(@"Do you want to start importing all report files in the Documents directory into this account?", nil) 
																			 delegate:self 
																	cancelButtonTitle:NSLocalizedString(@"Cancel", nil) 
																	otherButtonTitles:NSLocalizedString(@"Start Import", nil), nil] autorelease];
				confirmImportAlert.tag = kAlertTagConfirmImport;
				[confirmImportAlert show];
			}
		}
	} else if ([key isEqualToString:kExportReportsButton]) {
		[self doExport];
	} else if ([key hasPrefix:@"product.appstore."]) {
		NSString *productID = [key substringFromIndex:[@"product.appstore." length]];
		NSString *appStoreURLString = [NSString stringWithFormat:@"http://itunes.apple.com/app/id%@", productID];
		[[UIApplication sharedApplication] openURL:[NSURL URLWithString:appStoreURLString]];
	} else if ([key isEqualToString:kDeleteAccountButton]) {
		UIAlertView *confirmDeleteAlert = [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Delete Account?", nil) 
																	  message:NSLocalizedString(@"Do you really want to delete this account and all of its data?", nil) 
																	 delegate:self 
															cancelButtonTitle:NSLocalizedString(@"Cancel", nil) 
															otherButtonTitles:NSLocalizedString(@"Delete", nil), nil] autorelease];
		confirmDeleteAlert.tag = kAlertTagConfirmDelete;
		[confirmDeleteAlert show];
//	} else if ([key isEqualToString:@"SelectVendorIDButton"]) {
//		FieldEditorViewController *vc = nil;
//		if (self.presentedViewController) {
//			UINavigationController *nav = (UINavigationController *)self.presentedViewController;
//			vc = (FieldEditorViewController *)[[nav viewControllers] objectAtIndex:0];
//		} else {
//			vc = (FieldEditorViewController *)[self.navigationController.viewControllers lastObject];
//		}
//		NSString *token = [vc.values objectForKey:kAccountToken];
//		[vc dismissKeyboard];
//		
//		if (!token || token.length == 0) {
//			[[[[UIAlertView alloc] initWithTitle:nil message:NSLocalizedString(@"Please enter your iTunes Connect access token. To create an access token, login to iTunes Connect, visit the Sales and Trends module, then click 'Sales' and click 'Reports'.", nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", nil) otherButtonTitles:nil] autorelease] show];
//			return;
//		}
//		
//		NSDictionary *loginInfo = [NSDictionary dictionaryWithObjectsAndKeys:token, kAccountToken, nil];
//		
//		MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:vc.navigationController.view animated:YES];
//		hud.labelText = NSLocalizedString(@"Checking Vendor ID...", nil);
//		[hud showWhileExecuting:@selector(findVendorIDsWithLogin:) onTarget:self withObject:loginInfo animated:YES];
	} else if ([key isEqualToString:kDownloadBoxcarButton]) {
		if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"boxcar://provider/965"]]) {
			[[[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Boxcar Already Installed", nil) 
										 message:NSLocalizedString(@"The Boxcar app is already installed on your device. Please tap \"Add AppSales to Boxcar\" to start receiving push notifications.", nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", nil) otherButtonTitles:nil] autorelease] show];
		} else {
			[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"http://itunes.apple.com/app/boxcar/id321493542"]];
		}
	} else if ([key isEqualToString:kAddToBoxcarButton]) {
		if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"boxcar://provider/965"]]) {
			[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"boxcar://provider/965"]];
		} else {
			[[[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Boxcar Not Installed", nil) 
										 message:NSLocalizedString(@"The Boxcar app is not installed on your device. Please download it from the App Store and try again.", nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", nil) otherButtonTitles:nil] autorelease] show];
		}
	}
}

- (void)doExport
{
	NSString *docPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
	NSString *exportFolder = [self folderNameForExportingReportsOfAccount:self.selectedAccount];
	NSString *exportPath = [docPath stringByAppendingPathComponent:exportFolder];
	
	MBProgressHUD *hud = [MBProgressHUD showHUDAddedTo:self.navigationController.view animated:YES];
	hud.labelText = NSLocalizedString(@"Exporting...", nil);
	double delayInSeconds = 0.25;
	dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
	dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
		[[NSFileManager defaultManager] createDirectoryAtPath:exportPath withIntermediateDirectories:YES attributes:nil error:NULL];
		
		void (^exportBlock)(Report *report) = ^ (Report *report) { 
			NSString *csv = [report valueForKeyPath:@"originalReport.content"];
			NSString *filename = [report valueForKeyPath:@"originalReport.filename"];
			if ([filename hasSuffix:@".gz"]) {
				filename = [filename substringToIndex:filename.length - 3];
			}
			NSString *reportPath = [exportPath stringByAppendingPathComponent:filename];
			[csv writeToFile:reportPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
		};
		for (Report *dailyReport in self.selectedAccount.dailyReports) {
			exportBlock(dailyReport);
		}
		for (Report *weeklyReport in self.selectedAccount.weeklyReports) {
			exportBlock(weeklyReport);
		}
		
		self.exportedReportsZipPath = [exportPath stringByAppendingPathExtension:@"zip"];
		ZipFile *zipFile = [[ZipFile alloc] initWithFileName:self.exportedReportsZipPath mode:ZipFileModeCreate];
		NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:exportPath error:NULL];
		for (NSString *filename in files) {
			NSString *path = [exportPath stringByAppendingPathComponent:filename];
			NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
			NSDate *date = [attributes fileCreationDate];
			ZipWriteStream *stream = [zipFile writeFileInZipWithName:filename fileDate:date compressionLevel:ZipCompressionLevelBest];
			NSData *data = [NSData dataWithContentsOfFile:path];
			[stream writeData:data];
			[stream finishedWriting];
		}
		[zipFile close];
		[zipFile release];
		
		[[NSFileManager defaultManager] removeItemAtPath:exportPath error:NULL];
		
		[MBProgressHUD hideHUDForView:self.navigationController.view animated:YES];
		
		UIAlertView *exportCompletedAlert = [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Export Completed", nil) 
																		message:NSLocalizedString(@"The report files of this account have been exported as a Zip archive. You can now access the archive via iTunes file sharing or open it in a suitable app.", nil) 
																	   delegate:self 
															  cancelButtonTitle:NSLocalizedString(@"Done", nil) 
															  otherButtonTitles:NSLocalizedString(@"Open in...", nil), nil] autorelease];
		exportCompletedAlert.tag = kAlertTagExportCompleted;
		[exportCompletedAlert show];
	});
}

- (NSString *)folderNameForExportingReportsOfAccount:(ASAccount *)account
{
	NSString *folder = account.title;
	if (!folder || folder.length == 0) {
		folder = account.username;
	}
	if (!folder || folder.length == 0) {
		folder = @"Untitled Account";
	}
	folder = [folder stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
	folder = [folder stringByReplacingOccurrencesOfString:@":" withString:@"-"];
	
	NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
	[dateFormatter setDateFormat:@"YYYY-MM-dd"];
	NSString *dateString = [dateFormatter stringFromDate:[NSDate date]];
	[dateFormatter release];
	folder = [folder stringByAppendingFormat:@" %@", dateString];
	return folder;
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
	if (alertView.tag == kAlertTagConfirmImport) {
		if (buttonIndex != [alertView cancelButtonIndex]) {
			[[ReportDownloadCoordinator sharedReportDownloadCoordinator] importReportsIntoAccount:self.selectedAccount];
			[self.navigationController popViewControllerAnimated:YES];
		}
	} else if (alertView.tag == kAlertTagConfirmDelete) {
		if (buttonIndex != [alertView cancelButtonIndex]) {
			[self deleteAccount:self.selectedAccount];
			[self.navigationController popViewControllerAnimated:YES];
		}
	}
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
	if (alertView.tag == kAlertTagExportCompleted) {
		if (buttonIndex != alertView.cancelButtonIndex) {
			self.documentInteractionController = [UIDocumentInteractionController interactionControllerWithURL:[NSURL fileURLWithPath:self.exportedReportsZipPath]];
			self.documentInteractionController.delegate = self;
			BOOL couldPresentAppSelection = [self.documentInteractionController presentOpenInMenuFromRect:self.navigationController.view.bounds inView:self.navigationController.view animated:YES];
			if (!couldPresentAppSelection) {
				[[[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Error", nil) message:NSLocalizedString(@"You don't seem to have any app installed that can open Zip files.", nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", nil) otherButtonTitles:nil] autorelease] show];
			}
		}
	}
}

- (void)documentInteractionControllerDidDismissOpenInMenu:(UIDocumentInteractionController *)controller
{
	self.documentInteractionController = nil;
}

- (void)fieldEditorDidCancel:(FieldEditorViewController *)editor
{
	[editor dismissViewControllerAnimated:YES completion:nil];
}

- (void)didSettingsChanged:(KKPasscodeSettingsViewController*)viewController
{
  
  if ([[KKPasscodeLock sharedLock] isPasscodeRequired]) {
    passcodeLockField.defaultValue = @"On";
  } else {
    passcodeLockField.defaultValue = @"Off";
  }
  
  [settingsViewController.tableView reloadData];
}

#pragma mark -

- (void)saveContext
{
	NSError *error = nil;
	if (![[self managedObjectContext] save:&error]) { 
		NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
		abort();
	}
}

- (void)dealloc
{
	[refreshButtonItem release];
	[accounts release];
	[selectedAccount release];
	[managedObjectContext release];
	[exportedReportsZipPath release];
	[documentInteractionController release];
    [super dealloc];
}


@end
