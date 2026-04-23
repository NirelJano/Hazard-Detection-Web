#!/usr/bin/env python3
"""
Generates a minimal HazardDetection.xcodeproj from scratch.
Run from the HazardDetection/ folder:
    python3 generate_project.py
"""

import os, uuid, pathlib

def uid():
    return uuid.uuid4().hex[:24].upper()

# --- Fixed UUIDs so the project is stable ---
IDs = {
    "project":          uid(),
    "mainGroup":        uid(),
    "sourcesGroup":     uid(),
    "productsGroup":    uid(),
    "target":           uid(),
    "buildConfigDebug": uid(),
    "buildConfigRel":   uid(),
    "projConfigDebug":  uid(),
    "projConfigRel":    uid(),
    "configListProj":   uid(),
    "configListTarget": uid(),
    "sourcesBuildPhase":uid(),
    "resourcesBuildPhase":uid(),
    "frameworksBuildPhase":uid(),
    # Swift source files
    "fileApp":          uid(),
    "fileContent":      uid(),
    "fileCameraManager":uid(),
    "fileCameraView":   uid(),
    "fileDesign":       uid(),
    "fileLiveDetection":uid(),
    "fileBackend":       uid(),
    "fileAuth":          uid(),
    "fileAuthView":      uid(),
    "fileCloudinary":    uid(),
    "fileDashboard":     uid(),
    "fileGeocoding":     uid(),
    "fileLocation":      uid(),
    "fileMainTab":       uid(),
    "fileModels":        uid(),
    "fileReportDetail":  uid(),
    "fileSettings":      uid(),
    "fileUIComponents":  uid(),
    "fileUpload":        uid(),
    # build file refs
    "bfApp":            uid(),
    "bfContent":        uid(),
    "bfCameraManager":  uid(),
    "bfCameraView":     uid(),
    "bfDesign":         uid(),
    "bfLiveDetection":  uid(),
    "bfBackend":         uid(),
    "bfAuth":            uid(),
    "bfAuthView":        uid(),
    "bfCloudinary":      uid(),
    "bfDashboard":       uid(),
    "bfGeocoding":       uid(),
    "bfLocation":        uid(),
    "bfMainTab":         uid(),
    "bfModels":          uid(),
    "bfReportDetail":    uid(),
    "bfSettings":        uid(),
    "bfUIComponents":    uid(),
    "bfUpload":          uid(),
    # product
    "productFile":      uid(),
    # CoreML Model
    "fileModel":        uid(),
    "bfModel":          uid(),
    "fileModelC":       uid(),
    "bfModelC":         uid(),
    # Assets
    "fileAssets":       uid(),
    "bfAssets":         uid(),
    # Swift Packages
    "pkgFirebase":      uid(),
    "prodCore":         uid(),
    "prodAuth":         uid(),
    "prodFirestore":    uid(),
    "bfProdCore":       uid(),
    "bfProdAuth":       uid(),
    "bfProdFirestore":  uid(),
    # Firebase
    "fileGoogleService": uid(),
    "bfGoogleService":   uid(),
    # Images
    "filePng1":         uid(),
    "bfPng1":           uid(),
    "filePng2":         uid(),
    "bfPng2":           uid(),
    "filePng3":         uid(),
    "bfPng3":           uid(),
}

SWIFT_FILES = [
    ("HazardDetectionApp.swift", "fileApp",           "bfApp"),
    ("ContentView.swift",        "fileContent",        "bfContent"),
    ("CameraManager.swift",      "fileCameraManager",  "bfCameraManager"),
    ("CameraView.swift",         "fileCameraView",     "bfCameraView"),
    ("DesignSystem.swift",       "fileDesign",         "bfDesign"),
    ("LiveDetectionView.swift",  "fileLiveDetection",  "bfLiveDetection"),
    ("BackendServices.swift",    "fileBackend",        "bfBackend"),
    ("AuthManager.swift",        "fileAuth",           "bfAuth"),
    ("AuthenticationView.swift", "fileAuthView",       "bfAuthView"),
    ("CloudinaryService.swift",  "fileCloudinary",     "bfCloudinary"),
    ("DashboardView.swift",      "fileDashboard",      "bfDashboard"),
    ("GeocodingService.swift",   "fileGeocoding",      "bfGeocoding"),
    ("LocationManager.swift",    "fileLocation",       "bfLocation"),
    ("MainTabView.swift",        "fileMainTab",        "bfMainTab"),
    ("Models.swift",             "fileModels",         "bfModels"),
    ("ReportDetailView.swift",   "fileReportDetail",   "bfReportDetail"),
    ("SettingsView.swift",       "fileSettings",       "bfSettings"),
    ("UIComponents.swift",       "fileUIComponents",   "bfUIComponents"),
    ("UploadReportView.swift",   "fileUpload",         "bfUpload"),
]

PNG_FILES = [
    ("dashboard_map.png",     "filePng1", "bfPng1"),
    ("report_table.png",      "filePng2", "bfPng2"),
    ("static_detection.png",  "filePng3", "bfPng3"),
]

def pbxproj():
    I = IDs
    file_refs = ""
    for fname, fid, _ in SWIFT_FILES:
        file_refs += f"""\t\t{I[fid]} /* {fname} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {fname}; sourceTree = "<group>"; }};\n"""
    
    # Add CoreML model reference
    file_refs += f"""\t\t{I['fileModel']} /* best.mlpackage */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.mlpackage; path = best.mlpackage; sourceTree = "<group>"; }};\n"""
    file_refs += f"""\t\t{I['fileModelC']} /* best.mlmodelc */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.pbobjc; path = best.mlmodelc; sourceTree = "<group>"; }};\n"""
    
    # Add Assets reference
    file_refs += f"""\t\t{I['fileAssets']} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};\n"""
    file_refs += f"""\t\t{I['fileGoogleService']} /* GoogleService-Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "GoogleService-Info.plist"; sourceTree = "<group>"; }};\n"""

    for fname, fid, _ in PNG_FILES:
        file_refs += f"""\t\t{I[fid]} /* {fname} */ = {{isa = PBXFileReference; lastKnownFileType = image.png; path = {fname}; sourceTree = "<group>"; }};\n"""

    build_files = ""
    for fname, fid, bfid in SWIFT_FILES:
        build_files += f"\t\t{I[bfid]} /* {fname} in Sources */ = {{isa = PBXBuildFile; fileRef = {I[fid]} /* {fname} */; }};\n"
    
    # Add CoreML model to build files
    build_files += f"\t\t{I['bfModel']} /* best.mlpackage in Resources */ = {{isa = PBXBuildFile; fileRef = {I['fileModel']} /* best.mlpackage */; }};\n"
    build_files += f"\t\t{I['bfModelC']} /* best.mlmodelc in Resources */ = {{isa = PBXBuildFile; fileRef = {I['fileModelC']} /* best.mlmodelc */; }};\n"
    
    # Add Assets to build files
    build_files += f"""\t\t{I['bfAssets']} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {I['fileAssets']} /* Assets.xcassets */; }};\n"""
    build_files += f"""\t\t{I['bfGoogleService']} /* GoogleService-Info.plist in Resources */ = {{isa = PBXBuildFile; fileRef = {I['fileGoogleService']} /* GoogleService-Info.plist */; }};\n"""

    for fname, fid, bfid in PNG_FILES:
        build_files += f"\t\t{I[bfid]} /* {fname} in Resources */ = {{isa = PBXBuildFile; fileRef = {I[fid]} /* {fname} */; }};\n"

    build_files += f"\t\t{I['bfProdCore']} /* FirebaseCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['prodCore']} /* FirebaseCore */; }};\n"
    build_files += f"\t\t{I['bfProdAuth']} /* FirebaseAuth in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['prodAuth']} /* FirebaseAuth */; }};\n"
    build_files += f"\t\t{I['bfProdFirestore']} /* FirebaseFirestore in Frameworks */ = {{isa = PBXBuildFile; productRef = {I['prodFirestore']} /* FirebaseFirestore */; }};\n"

    sources_children = "\n".join(f"\t\t\t\t{I[fid]} /* {fname} */," for fname,fid,_ in SWIFT_FILES)
    sources_build_files = "\n".join(f"\t\t\t\t{I[bfid]} /* {fname} in Sources */," for _,_,bfid in SWIFT_FILES)

    return f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{build_files}/* End PBXBuildFile section */

/* Begin PBXFileReference section */
\t\t{I['productFile']} /* HazardDetection.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = HazardDetection.app; sourceTree = BUILT_PRODUCTS_DIR; }};
{file_refs}/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{I['frameworksBuildPhase']} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{I['bfProdCore']} /* FirebaseCore in Frameworks */,
\t\t\t\t{I['bfProdAuth']} /* FirebaseAuth in Frameworks */,
\t\t\t\t{I['bfProdFirestore']} /* FirebaseFirestore in Frameworks */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{I['mainGroup']} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['sourcesGroup']} /* HazardDetection */,
\t\t\t\t{I['productsGroup']} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{I['productsGroup']} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{I['productFile']} /* HazardDetection.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};
\t\t{I['sourcesGroup']} /* HazardDetection */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{sources_children}
\t\t\t\t{I['fileAssets']} /* Assets.xcassets */,
\t\t\t\t{I['fileGoogleService']} /* GoogleService-Info.plist */,
\t\t\t\t{I['fileModel']} /* best.mlpackage */,
\t\t\t\t{I['fileModelC']} /* best.mlmodelc */,
\t\t\t\t{I['filePng1']} /* dashboard_map.png */,
\t\t\t\t{I['filePng2']} /* report_table.png */,
\t\t\t\t{I['filePng3']} /* static_detection.png */,
\t\t\t);
\t\t\tpath = HazardDetection;
\t\t\tsourceTree = "<group>";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{I['target']} /* HazardDetection */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {I['configListTarget']} /* Build configuration list for PBXNativeTarget "HazardDetection" */;
\t\t\tbuildPhases = (
\t\t\t\t{I['sourcesBuildPhase']} /* Sources */,
\t\t\t\t{I['frameworksBuildPhase']} /* Frameworks */,
\t\t\t\t{I['resourcesBuildPhase']} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = HazardDetection;
\t\t\tpackageProductDependencies = (
\t\t\t\t{I['prodCore']} /* FirebaseCore */,
\t\t\t\t{I['prodAuth']} /* FirebaseAuth */,
\t\t\t\t{I['prodFirestore']} /* FirebaseFirestore */,
\t\t\t);
\t\t\tproductName = HazardDetection;
\t\t\tproductReference = {I['productFile']} /* HazardDetection.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{I['project']} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1500;
\t\t\t\tLastUpgradeCheck = 1500;
\t\t\t}};
\t\t\tbuildConfigurationList = {I['configListProj']} /* Build configuration list for PBXProject "HazardDetection" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {I['mainGroup']};
\t\t\tpackageReferences = (
\t\t\t\t{I['pkgFirebase']} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */,
\t\t\t);
\t\t\tproductRefGroup = {I['productsGroup']} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{I['target']} /* HazardDetection */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{I['resourcesBuildPhase']} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{I['bfAssets']} /* Assets.xcassets in Resources */,
\t\t\t\t{I['bfGoogleService']} /* GoogleService-Info.plist in Resources */,
\t\t\t\t{I['bfModel']} /* best.mlpackage in Resources */,
\t\t\t\t{I['bfModelC']} /* best.mlmodelc in Resources */,
\t\t\t\t{I['bfPng1']} /* dashboard_map.png in Resources */,
\t\t\t\t{I['bfPng2']} /* report_table.png in Resources */,
\t\t\t\t{I['bfPng3']} /* static_detection.png in Resources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{I['sourcesBuildPhase']} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{sources_build_files}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCRemoteSwiftPackageReference section */
\t\t{I['pkgFirebase']} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */ = {{
\t\t\tisa = XCRemoteSwiftPackageReference;
\t\t\trepositoryURL = "https://github.com/firebase/firebase-ios-sdk";
\t\t\trequirement = {{
\t\t\t\tkind = upToNextMajorVersion;
\t\t\t\tminimumVersion = 10.0.0;
\t\t\t}};
\t\t}};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
\t\t{I['prodCore']} /* FirebaseCore */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {I['pkgFirebase']} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */;
\t\t\tproductName = FirebaseCore;
\t\t}};
\t\t{I['prodAuth']} /* FirebaseAuth */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {I['pkgFirebase']} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */;
\t\t\tproductName = FirebaseAuth;
\t\t}};
\t\t{I['prodFirestore']} /* FirebaseFirestore */ = {{
\t\t\tisa = XCSwiftPackageProductDependency;
\t\t\tpackage = {I['pkgFirebase']} /* XCRemoteSwiftPackageReference "firebase-ios-sdk" */;
\t\t\tproductName = FirebaseFirestore;
\t\t}};
/* End XCSwiftPackageProductDependency section */

/* Begin XCBuildConfiguration section */
\t\t{I['buildConfigDebug']} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSET_SYMBOL_GENERATION = NO;
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSET_CATALOG_COMPILER_OPTIMIZATION = space;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tINFOPLIST_FILE = HazardDetection/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "com.raz0125.hazarddetection.app";
\t\t\t\tDEVELOPMENT_TEAM = 8NX9TVG3J6;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_VERSION = 5.9;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{I['buildConfigRel']} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSET_SYMBOL_GENERATION = NO;
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSET_CATALOG_COMPILER_OPTIMIZATION = space;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tINFOPLIST_FILE = HazardDetection/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "com.raz0125.hazarddetection.app";
\t\t\t\tDEVELOPMENT_TEAM = 8NX9TVG3J6;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_VERSION = 5.9;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{I['projConfigDebug']} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{I['projConfigRel']} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t{I['configListProj']} /* Build configuration list for PBXProject "HazardDetection" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{I['projConfigDebug']} /* Debug */,
\t\t\t\t{I['projConfigRel']} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{I['configListTarget']} /* Build configuration list for PBXNativeTarget "HazardDetection" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{I['buildConfigDebug']} /* Debug */,
\t\t\t\t{I['buildConfigRel']} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */

\t}};
\trootObject = {I['project']} /* Project object */;
}}
"""

def xcscheme(target_id, project_name):
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeCheck = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{target_id}"
               BuildableName = "{project_name}.app"
               BlueprintName = "{project_name}"
               ReferencedContainer = "container:{project_name}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_id}"
            BuildableName = "{project_name}.app"
            BlueprintName = "{project_name}"
            ReferencedContainer = "container:{project_name}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target_id}"
            BuildableName = "{project_name}.app"
            BlueprintName = "{project_name}"
            ReferencedContainer = "container:{project_name}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""

def main():
    base = pathlib.Path(__file__).parent
    proj_dir = base / "HazardDetection.xcodeproj"
    proj_dir.mkdir(exist_ok=True)

    pbx_path = proj_dir / "project.pbxproj"
    pbx_path.write_text(pbxproj())
    print(f"✅  Generated: {pbx_path}")

    # Generate Scheme
    scheme_dir = proj_dir / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    scheme_path = scheme_dir / "HazardDetection.xcscheme"
    scheme_path.write_text(xcscheme(IDs['target'], "HazardDetection"))
    print(f"✅  Generated: {scheme_path}")

    print("👉  Open with: open HazardDetection.xcodeproj")

if __name__ == "__main__":
    main()
