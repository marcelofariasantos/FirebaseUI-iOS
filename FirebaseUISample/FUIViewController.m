//
//  Copyright (c) 2016 Google Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "FUIViewController.h"
#import <FirebaseAuth/FirebaseAuth.h>
#import <FirebaseAuthUI/FirebaseAuthUI.h>
#import <FirebaseCore/FIRApp.h>
#import <FirebaseGoogleAuthUI/FirebaseGoogleAuthUI.h>
#import <FirebaseFacebookAuthUI/FirebaseFacebookAuthUI.h>
#import <FirebaseTwitterAuthUI/FirebaseTwitterAuthUI.h>
#import <OCMock/OCMock.h>

typedef NS_ENUM(NSUInteger, UISections) {
  kSectionsSignedInAs = 0,
  kSectionsSimulationBehavior,
  kSectionsProviders,
  kSectionsAccountManager
};

typedef NS_ENUM(NSUInteger, FIRSimulationChoise) {
  kSimulationNoMocks = 0,
  kSimulationExistingUser,
  kSimulationNewUser,
  kSimulationEmailRecovery,
  kSimulationUnknown,
};

typedef NS_ENUM(NSUInteger, FIRProviders) {
  kIDPEmail = 0,
  kIDPGoogle,
  kIDPFacebook,
  kIDPTwitter
};

@interface FUIViewController () <FUIAuthDelegate, NSURLSessionDataDelegate>
@property (weak, nonatomic) IBOutlet UIBarButtonItem *btnAuthorization;
@property (weak, nonatomic) IBOutlet UILabel *labelUserEmail;
@property (nonatomic, assign) FIRSimulationChoise selectedSimulationChoise;

@property (nonatomic) id authMock;
@property (nonatomic) id authUIMock;
@property (nonatomic) FIRAuthStateDidChangeListenerHandle authStateDidChangeHandle;

@end

@implementation FUIViewController

- (void)viewDidLoad {
  [super viewDidLoad];

  [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:kSimulationNoMocks
                                                          inSection:kSectionsSimulationBehavior]
                              animated:NO
                        scrollPosition:UITableViewScrollPositionNone];

  [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:kIDPEmail
                                                          inSection:kSectionsProviders]
                              animated:NO
                        scrollPosition:UITableViewScrollPositionNone];
}

- (IBAction)onAuthorization:(id)sender {
  [self prepareStubs];
  UIViewController *controller = [self.authUIMock authViewController];
  [self presentViewController:controller animated:YES completion:nil];
}


#pragma mark - UITableViewControllerDelegate methods

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  if (indexPath.section != kSectionsProviders) {
    _selectedSimulationChoise = indexPath.row;
    [self deselectAllCellsExcept:indexPath];
  }

  [self prepareStubsForTests];

  if (indexPath.section == kSectionsAccountManager) {
    switch (indexPath.row) {
      case 0:
        [self prepareForAccountManagerWithPasswordWithoutLinkedAccount];
        break;
      case 1:
        [self prepareForAccountManagerWithPasswordWithLinkedAccountWithEmail];
        break;
      case 2:
        [self prepareForAccountManagerWithPasswordWithLinkedAccountWithoutEmail];
        break;
      case 3:
        [self prepareForAccountManagerWithoutPasswordWithLinkedAccountWithoutEmail];
        break;
      case 4:
        [self prepareForAccountManagerWithoutPasswordWithLinkedAccountWithEmail];
        break;

      default:
        break;
    }

    [self mockServerOperations];

    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    [self showAccountManager];
  }
}

- (void)deselectAllCellsExcept:(NSIndexPath *)indexPath {

  NSInteger count = [self tableView:self.tableView numberOfRowsInSection:indexPath.section];
  for (NSInteger index = 0; index < count; index++) {
    if (index != indexPath.row) {
      [self.tableView deselectRowAtIndexPath:[NSIndexPath indexPathForRow:index
                                                                inSection:indexPath.section]
                                    animated:YES];
    }
  }
}

#pragma mark - FUIAuthDelegate methods

- (void)authUI:(FUIAuth *)authUI didSignInWithUser:(nullable FIRUser *)user error:(nullable NSError *)error {
  if (error) {
    if (error.code == FUIAuthErrorCodeUserCancelledSignIn) {
      [self showAlert:@"User cancelled sign-in"];
    } else {
      NSError *detailedError = error.userInfo[NSUnderlyingErrorKey];
      if (!detailedError) {
        detailedError = error;
      }
      [self showAlert:detailedError.localizedDescription];
    }
  } else {
    _labelUserEmail.text = user.email;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:kSectionsSignedInAs]
                  withRowAnimation:UITableViewRowAnimationNone];
  }
}

- (void)showAlert:(NSString *)message {
  UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                 message:message
                                                          preferredStyle:UIAlertControllerStyleAlert];
  UIAlertAction* closeButton = [UIAlertAction
                                actionWithTitle:@"Close"
                                style:UIAlertActionStyleDefault
                                handler:nil];
  [alert addAction:closeButton];
  [self presentViewController:alert animated:YES completion:nil];

}

#pragma mark - helper methods

- (void)prepareStubs {

  [self prepareStubsForTests];

  switch (_selectedSimulationChoise) {
    case kSimulationUnknown:
      [self prepareGenuineExample];
      break;
    case kSimulationExistingUser:
      [self prepareStubsForSimulationExistingUser];
      break;
    case kSimulationNewUser:
      [self prepareStubsForSimulationNewUser];
      break;
    case kSimulationEmailRecovery:
      [self prepareStubsForEmailRecovery];
      break;

    default:
      break;
  }
}

- (void)prepareGenuineExample {
  self.authMock = [FIRAuth auth];
  self.authUIMock = [self configureFirAuthUI];

}

- (void)prepareStubsForTests {
  [self.authMock stopMocking];
  self.authMock = OCMPartialMock([FIRAuth auth]);

  OCMStub(ClassMethod([self.authMock auth])).andReturn(self.authMock);

  [self.authUIMock stopMocking];
  self.authUIMock = OCMPartialMock([self configureFirAuthUI]);
  OCMStub([self.authUIMock auth]).andReturn(self.authMock);
}

- (void)prepareStubsForSimulationExistingUser {
  OCMStub([self.authMock fetchProvidersForEmail:OCMOCK_ANY completion:OCMOCK_ANY]).andDo(^(NSInvocation *invocation) {
    FIRProviderQueryCallback mockedCallback;
    [invocation getArgument:&mockedCallback atIndex:3];
    mockedCallback(@[@"password"], nil);
  });


  [self mockSignInWithEmail];
}

- (void)prepareStubsForSimulationNewUser {
  OCMStub([self.authMock fetchProvidersForEmail:OCMOCK_ANY completion:OCMOCK_ANY]).andDo(^(NSInvocation *invocation) {
    FIRProviderQueryCallback mockedResponse;
    [invocation getArgument:&mockedResponse atIndex:3];
    mockedResponse(nil, nil);
  });


  OCMStub([self.authMock createUserWithEmail:OCMOCK_ANY password:OCMOCK_ANY completion:OCMOCK_ANY]).andDo(^(NSInvocation *invocation) {
    FIRAuthResultCallback mockedCallback;
    [invocation getArgument:&mockedCallback atIndex:4];

    NSString *responseEmail;
    [invocation getArgument:&responseEmail atIndex:2];

    id mockUser = OCMClassMock([FIRUser class]);
    OCMStub([mockUser email]).andReturn(responseEmail);
    [self mockUpdateUserRequest:mockUser];

    mockedCallback(mockUser, nil);
  });

}

- (void)prepareStubsForEmailRecovery {
  OCMStub([self.authMock fetchProvidersForEmail:OCMOCK_ANY completion:OCMOCK_ANY]).andDo(^(NSInvocation *invocation) {
    FIRProviderQueryCallback mockedCallback;
    [invocation getArgument:&mockedCallback atIndex:3];
    mockedCallback(@[@"password"], nil);
  });

  OCMStub([self.authMock sendPasswordResetWithEmail:OCMOCK_ANY completion:OCMOCK_ANY]).andDo(^(NSInvocation *invocation) {
    FIRSendPasswordResetCallback mockedCallback;
    [invocation getArgument:&mockedCallback atIndex:3];
    mockedCallback(nil);
  });

}

- (NSArray *)getListOfIDPs {
  NSArray<NSIndexPath *> *selectedRows = [self.tableView indexPathsForSelectedRows];
  NSMutableArray *providers = [NSMutableArray new];

  for (NSIndexPath *indexPath in selectedRows) {
    if (indexPath.section == kSectionsProviders) {
      switch (indexPath.row) {
        case kIDPGoogle:
          [providers addObject:[[FUIGoogleAuth alloc] init]];
          break;
        case kIDPFacebook:
          [providers addObject:[[FUIFacebookAuth alloc] init]];
          break;
        case kIDPTwitter:
          [providers addObject:[[FUITwitterAuth alloc] init]];
          break;

        default:
          break;
      }
    }
  }

  return providers;
}

- (BOOL)isEmailEnabled {
  NSArray<NSIndexPath *> *selectedRows = [self.tableView indexPathsForSelectedRows];
  return [selectedRows containsObject:[NSIndexPath
                                       indexPathForRow:kIDPEmail
                                       inSection:kSectionsProviders]];
}

- (FUIAuth *)configureFirAuthUI {
  FUIAuth *authUI = [FUIAuth defaultAuthUI];
  authUI.providers = [self getListOfIDPs];
  authUI.signInWithEmailHidden = ![self isEmailEnabled];
  authUI.delegate = self;
  return authUI;
}

- (void)showAccountManager {
  UIViewController *controller =
      [[FUIAccountSettingsViewController alloc] initWithAuthUI:self.authUIMock];
  [self.navigationController pushViewController:controller animated:YES];
}

- (void)prepareForAccountManagerWithPasswordWithoutLinkedAccount {
  id mockUser = [self mockUserWhichHasEmail:YES];

  // Add EmailPassword provider
  id emailPasswordProviderMock = [self createPasswordProvider];

  // Stub providerData
  NSArray *providers = [NSArray arrayWithObject:emailPasswordProviderMock];
  OCMStub([mockUser providerData]).andReturn(providers);

}

- (void)prepareForAccountManagerWithPasswordWithLinkedAccountWithEmail {
  id mockUser = [self mockUserWhichHasEmail:YES];

  //Add EmailPassword provider
  id emailPasswordProviderMock = [self createPasswordProvider];

  //Add third party provider with email
  id linkedProviderMock = [self createThirdPartyProvider:FIRGoogleAuthProviderID hasEmail:YES];

  // Stub providerData
  NSArray *providers =
      [NSArray arrayWithObjects:emailPasswordProviderMock, linkedProviderMock, nil];
  OCMStub([mockUser providerData]).andReturn(providers);
}

- (void)prepareForAccountManagerWithPasswordWithLinkedAccountWithoutEmail {
  id mockUser = [self mockUserWhichHasEmail:YES];

  //Add third party provider without email
  id linkedProviderMock = [self createThirdPartyProvider:FIRGoogleAuthProviderID hasEmail:NO];

  //Add EmailPassword provider
  id emailPasswordProviderMock = [self createPasswordProvider];

  // Stub providerData
  NSArray *providers =
      [NSArray arrayWithObjects:emailPasswordProviderMock, linkedProviderMock, nil];
  OCMStub([mockUser providerData]).andReturn(providers);
}

- (void)prepareForAccountManagerWithoutPasswordWithLinkedAccountWithoutEmail {
  id mockUser = [self mockUserWhichHasEmail:NO];

  //Add third party provider without email
  id linkedProviderMock = [self createThirdPartyProvider:FIRGoogleAuthProviderID hasEmail:NO];

  // Stub providerData
  NSArray *providers = [NSArray arrayWithObject:linkedProviderMock];
  OCMStub([mockUser providerData]).andReturn(providers);
}

- (void)prepareForAccountManagerWithoutPasswordWithLinkedAccountWithEmail {
  id mockUser = [self mockUserWhichHasEmail:YES];

  //Add third party provider with email
  id linkedProviderMock = [self createThirdPartyProvider:FIRGoogleAuthProviderID hasEmail:YES];

  // Stub providerData
  NSArray *providers = [NSArray arrayWithObject:linkedProviderMock];
  OCMStub([mockUser providerData]).andReturn(providers);
}

#pragma mark - stubbing methods

- (id)createPasswordProvider {
  id emailPasswordProviderMock = OCMProtocolMock(@protocol(FIRUserInfo));
  OCMStub([emailPasswordProviderMock providerID]).andReturn(FIREmailPasswordAuthProviderID);
  OCMStub([emailPasswordProviderMock email]).andReturn(@"password@email.com");
  OCMStub([emailPasswordProviderMock displayName]).andReturn(@"password displayName");

  return emailPasswordProviderMock;
}

- (id)createThirdPartyProvider:(NSString *)providerId hasEmail:(BOOL)hasEmail {
  id linkedProviderMock = OCMProtocolMock(@protocol(FIRUserInfo));
  OCMStub([linkedProviderMock providerID]).andReturn(providerId);
  OCMStub([linkedProviderMock displayName]).andReturn(@"linked displayName");
  if (hasEmail) {
    OCMStub([linkedProviderMock email]).andReturn(@"linked@email.com");
  }
  return linkedProviderMock;
}

- (id)mockUserWhichHasEmail:(BOOL)hasEmail {
  id mockUser = OCMClassMock([FIRUser class]);
  OCMStub([self.authMock currentUser]).andReturn(mockUser);

  // Mock User display values
  if (hasEmail) {
    OCMStub([mockUser email]).andReturn(@"email@email.com");
  }
  OCMStub([mockUser displayName]).andReturn(@"user displayName");

  return mockUser;
}

- (void)mockUpdateUserRequest:(id)mockUser {
  id mockRequest = OCMClassMock([FIRUserProfileChangeRequest class]);
  OCMStub([mockUser profileChangeRequest]).andReturn(mockRequest);
  OCMStub([mockRequest commitChangesWithCompletion:OCMOCK_ANY]).andDo(^(NSInvocation *invocation) {
    FIRUserProfileChangeCallback mockedCallBack;
    [invocation getArgument:&mockedCallBack atIndex:2];
    mockedCallBack(nil);
  });
}

- (void)mockSignInWithEmail {
  OCMStub([self.authMock signInWithEmail:OCMOCK_ANY password:OCMOCK_ANY completion:OCMOCK_ANY]).
      andDo(^(NSInvocation *invocation) {
    FIRAuthResultCallback mockedResponse;
    [invocation getArgument:&mockedResponse atIndex:4];

    NSString *responseEmail;
    [invocation getArgument:&responseEmail atIndex:2];

    id mockUser = OCMClassMock([FIRUser class]);
    OCMStub([mockUser email]).andReturn(responseEmail);
    
    mockedResponse(mockUser, nil);
  });
}

- (void)mockUpdatePasswordRequest:(id)mockUser {
  OCMStub([mockUser updatePassword:OCMOCK_ANY completion:OCMOCK_ANY]).
      andDo(^(NSInvocation *invocation) {
    FIRUserProfileChangeCallback mockedCallBack;
    [invocation getArgument:&mockedCallBack atIndex:3];
    mockedCallBack(nil);
  });
}

- (void)mockSignOut {
  OCMStub([self.authUIMock signOutWithError:[OCMArg setTo:nil]]);
}

- (void)mockDeleteUserRequest:(id)mockUser {
  OCMStub([mockUser deleteWithCompletion:OCMOCK_ANY]).
      andDo(^(NSInvocation *invocation) {
    FIRUserProfileChangeCallback mockedCallBack;
    [invocation getArgument:&mockedCallBack atIndex:2];
    mockedCallBack(nil);
  });
}

- (void)mockUpdateEmail:(id)mockUser {
  OCMStub([mockUser updateEmail:OCMOCK_ANY completion:OCMOCK_ANY]).
      andDo(^(NSInvocation *invocation) {
    FIRUserProfileChangeCallback mockedCallBack;
    [invocation getArgument:&mockedCallBack atIndex:3];
    mockedCallBack(nil);
  });
}

- (void)mockSignInWithProvider:(NSString *)providerId user:(id)mockUser {
  id mockProviderUI = OCMProtocolMock(@protocol(FUIAuthProvider));
  NSArray *providers = [NSArray arrayWithObject:mockProviderUI];
  OCMStub([self.authUIMock providers]).andReturn(providers);

  OCMStub([mockProviderUI signOut]);
  OCMStub([mockProviderUI providerID]).andReturn(providerId);

  OCMStub([mockUser reauthenticateWithCredential:OCMOCK_ANY completion:OCMOCK_ANY]).
      andDo(^(NSInvocation *invocation) {
    FIRUserProfileChangeCallback mockedCallBack;
    [invocation getArgument:&mockedCallBack atIndex:3];

    mockedCallBack(nil);
  });

  OCMStub([mockProviderUI signInWithEmail:OCMOCK_ANY
                 presentingViewController:OCMOCK_ANY
                               completion:OCMOCK_ANY]).
      andDo(^(NSInvocation *invocation) {
    FIRAuthProviderSignInCompletionBlock mockedResponse;
    [invocation getArgument:&mockedResponse atIndex:4];

    id mockCredential = OCMClassMock([FIRAuthCredential class]);
    mockedResponse(mockCredential, nil);
  });
}

- (void)mockUnlinkOperation:(id)mockUser {
  OCMStub([mockUser unlinkFromProvider:OCMOCK_ANY completion:OCMOCK_ANY]).
      andDo(^(NSInvocation *invocation) {
    FIRAuthResultCallback mockedCallBack;
    [invocation getArgument:&mockedCallBack atIndex:3];

    mockedCallBack(mockUser, nil);
  });
}

- (void)mockServerOperations {
  id mockUser = [self.authMock currentUser];

  // Mock update name request
  [self mockUpdateUserRequest:mockUser];

  // Mock udpate email operation
  [self mockUpdateEmail:mockUser];

  // mock re-authentication with email
  [self mockSignInWithEmail];

  // mock update password
  [self mockUpdatePasswordRequest:mockUser];

  // mock sign out
  [self mockSignOut];

  // mock delete user
  [self mockDeleteUserRequest:mockUser];

  // mock re-authentication with 3P provider
  [self mockSignInWithProvider:FIRGoogleAuthProviderID user:mockUser];

  // mock unlinking 3P provider
  [self mockUnlinkOperation:mockUser];
}

@end
