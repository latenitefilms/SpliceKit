// SpliceKitBRAWToolboxCheck.h — gate BRAW features on Braw Toolbox presence.
//
// SpliceKit's BRAW integration is only enabled when the user has a valid
// Mac App Store copy of LateNite Films' Braw Toolbox installed. The check
// validates the app's code signature (Team ID + Apple Mac OS Application
// Signing certificate authority) so substituting an arbitrary app with the
// same bundle ID doesn't bypass the gate.
//
// Pattern mirrors CommandPost's LateNite-app validation in MJAppDelegate.m.

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

// Returns YES if a valid Mac App Store copy of com.latenitefilms.BRAWToolbox
// (team A5HDJTY9X5, signed by Apple Mac OS Application Signing) is installed.
// Result is cached after first call. Set the NSUserDefaults key
// SpliceKitBypassBRAWToolboxCheck=YES to force YES (development only).
BOOL SpliceKit_isBRAWToolboxInstalled(void);

#ifdef __cplusplus
}
#endif
