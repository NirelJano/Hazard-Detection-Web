#!/usr/bin/env python3
"""
Generates a minimal HazardDetection.xcodeproj from the files on disk.
Run from anywhere:
    python3 ios-app/HazardDetection/generate_project.py
"""

import pathlib
import uuid


PROJECT_NAME = "HazardDetection"
TEAM_ID = "Z3XLCBKN9K"
BUNDLE_ID = "com.hazarddetection.app-com.hazarddetection.app-"
FIREBASE_VERSION = "12.12.1"


def uid():
    return uuid.uuid4().hex[:24].upper()


def q(value):
    return '"' + value.replace('"', '\\"') + '"'


def swift_files(base):
    source_root = base / PROJECT_NAME
    return sorted(
        path.relative_to(source_root).as_posix()
        for path in source_root.rglob("*.swift")
    )


def pbxproj(files):
    ids = {
        "project": uid(),
        "main_group": uid(),
        "sources_group": uid(),
        "products_group": uid(),
        "target": uid(),
        "product_file": uid(),
        "sources_phase": uid(),
        "resources_phase": uid(),
        "frameworks_phase": uid(),
        "config_list_project": uid(),
        "config_list_target": uid(),
        "debug_project": uid(),
        "release_project": uid(),
        "debug_target": uid(),
        "release_target": uid(),
        "pkg_firebase": uid(),
        "prod_core": uid(),
        "prod_auth": uid(),
        "prod_firestore": uid(),
        "bf_core": uid(),
        "bf_auth": uid(),
        "bf_firestore": uid(),
    }

    source_refs = {}
    source_builds = {}
    for file in files:
        source_refs[file] = uid()
        source_builds[file] = uid()

    resources = [
        ("Assets.xcassets", "folder.assetcatalog"),
        ("GoogleService-Info.plist", "text.plist.xml"),
        ("best.mlpackage", "wrapper.mlpackage"),
        ("best.mlmodelc", "wrapper.pbobjc"),
        ("dashboard_map.png", "image.png"),
        ("report_table.png", "image.png"),
        ("static_detection.png", "image.png"),
    ]
    resource_refs = {name: uid() for name, _ in resources}
    resource_builds = {name: uid() for name, _ in resources}

    build_files = []
    for file in files:
        build_files.append(
            f"\t\t{source_builds[file]} /* {file} in Sources */ = "
            f"{{isa = PBXBuildFile; fileRef = {source_refs[file]} /* {file} */; }};"
        )
    for name, _ in resources:
        build_files.append(
            f"\t\t{resource_builds[name]} /* {name} in Resources */ = "
            f"{{isa = PBXBuildFile; fileRef = {resource_refs[name]} /* {name} */; }};"
        )
    build_files.extend([
        f"\t\t{ids['bf_core']} /* FirebaseCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {ids['prod_core']} /* FirebaseCore */; }};",
        f"\t\t{ids['bf_auth']} /* FirebaseAuth in Frameworks */ = {{isa = PBXBuildFile; productRef = {ids['prod_auth']} /* FirebaseAuth */; }};",
        f"\t\t{ids['bf_firestore']} /* FirebaseFirestore in Frameworks */ = {{isa = PBXBuildFile; productRef = {ids['prod_firestore']} /* FirebaseFirestore */; }};",
    ])

    file_refs = [
        f"\t\t{ids['product_file']} /* {PROJECT_NAME}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {PROJECT_NAME}.app; sourceTree = BUILT_PRODUCTS_DIR; }};"
    ]
    for file in files:
        file_refs.append(
            f"\t\t{source_refs[file]} /* {file} */ = "
            f"{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(file)}; sourceTree = \"<group>\"; }};"
        )
    for name, file_type in resources:
        file_refs.append(
            f"\t\t{resource_refs[name]} /* {name} */ = "
            f"{{isa = PBXFileReference; lastKnownFileType = {file_type}; path = {q(name)}; sourceTree = \"<group>\"; }};"
        )

    source_children = "\n".join(
        f"\t\t\t\t{source_refs[file]} /* {file} */," for file in files
    )
    resource_children = "\n".join(
        f"\t\t\t\t{resource_refs[name]} /* {name} */," for name, _ in resources
    )
    source_phase_files = "\n".join(
        f"\t\t\t\t{source_builds[file]} /* {file} in Sources */," for file in files
    )
    resource_phase_files = "\n".join(
        f"\t\t\t\t{resource_builds[name]} /* {name} in Resources */," for name, _ in resources
    )

    project_text = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{}};
\tobjectVersion = 56;
\tobjects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_files)}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(file_refs)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t{ids['frameworks_phase']} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t{ids['bf_core']} /* FirebaseCore in Frameworks */,
\t\t\t\t{ids['bf_auth']} /* FirebaseAuth in Frameworks */,
\t\t\t\t{ids['bf_firestore']} /* FirebaseFirestore in Frameworks */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
\t\t{ids['main_group']} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{ids['sources_group']} /* {PROJECT_NAME} */,
\t\t\t\t{ids['products_group']} /* Products */,
\t\t\t);
\t\t\tsourceTree = \"<group>\";
\t\t}};
\t\t{ids['products_group']} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{ids['product_file']} /* {PROJECT_NAME}.app */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = \"<group>\";
\t\t}};
\t\t{ids['sources_group']} /* {PROJECT_NAME} */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
{source_children}
{resource_children}
\t\t\t);
\t\t\tpath = {PROJECT_NAME};
\t\t\tsourceTree = \"<group>\";
\t\t}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t{ids['target']} /* {PROJECT_NAME} */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {ids['config_list_target']} /* Build configuration list for PBXNativeTarget \"{PROJECT_NAME}\" */;
\t\t\tbuildPhases = (
\t\t\t\t{ids['sources_phase']} /* Sources */,
\t\t\t\t{ids['frameworks_phase']} /* Frameworks */,
\t\t\t\t{ids['resources_phase']} /* Resources */,
\t\t\t);
\t\t\tbuildRules = ();
\t\t\tdependencies = ();
\t\t\tname = {PROJECT_NAME};
\t\t\tpackageProductDependencies = (
\t\t\t\t{ids['prod_core']} /* FirebaseCore */,
\t\t\t\t{ids['prod_auth']} /* FirebaseAuth */,
\t\t\t\t{ids['prod_firestore']} /* FirebaseFirestore */,
\t\t\t);
\t\t\tproductName = {PROJECT_NAME};
\t\t\tproductReference = {ids['product_file']} /* {PROJECT_NAME}.app */;
\t\t\tproductType = \"com.apple.product-type.application\";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t{ids['project']} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastSwiftUpdateCheck = 1500;
\t\t\t\tLastUpgradeCheck = 1500;
\t\t\t}};
\t\t\tbuildConfigurationList = {ids['config_list_project']} /* Build configuration list for PBXProject \"{PROJECT_NAME}\" */;
\t\t\tcompatibilityVersion = \"Xcode 14.0\";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (en, Base);
\t\t\tmainGroup = {ids['main_group']};
\t\t\tpackageReferences = (
\t\t\t\t{ids['pkg_firebase']} /* XCRemoteSwiftPackageReference \"firebase-ios-sdk\" */,
\t\t\t);
\t\t\tproductRefGroup = {ids['products_group']} /* Products */;
\t\t\tprojectDirPath = \"\";
\t\t\tprojectRoot = \"\";
\t\t\ttargets = (
\t\t\t\t{ids['target']} /* {PROJECT_NAME} */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t{ids['resources_phase']} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{resource_phase_files}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t{ids['sources_phase']} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{source_phase_files}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin XCRemoteSwiftPackageReference section */
\t\t{ids['pkg_firebase']} /* XCRemoteSwiftPackageReference \"firebase-ios-sdk\" */ = {{
\t\t\tisa = XCRemoteSwiftPackageReference;
\t\t\trepositoryURL = \"https://github.com/firebase/firebase-ios-sdk\";
\t\t\trequirement = {{
\t\t\t\tkind = upToNextMajorVersion;
\t\t\t\tminimumVersion = {FIREBASE_VERSION};
\t\t\t}};
\t\t}};
/* End XCRemoteSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
\t\t{ids['prod_core']} /* FirebaseCore */ = {{isa = XCSwiftPackageProductDependency; package = {ids['pkg_firebase']} /* XCRemoteSwiftPackageReference \"firebase-ios-sdk\" */; productName = FirebaseCore; }};
\t\t{ids['prod_auth']} /* FirebaseAuth */ = {{isa = XCSwiftPackageProductDependency; package = {ids['pkg_firebase']} /* XCRemoteSwiftPackageReference \"firebase-ios-sdk\" */; productName = FirebaseAuth; }};
\t\t{ids['prod_firestore']} /* FirebaseFirestore */ = {{isa = XCSwiftPackageProductDependency; package = {ids['pkg_firebase']} /* XCRemoteSwiftPackageReference \"firebase-ios-sdk\" */; productName = FirebaseFirestore; }};
/* End XCSwiftPackageProductDependency section */

/* Begin XCBuildConfiguration section */
\t\t{ids['debug_target']} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbaseConfigurationReference = 8BBED19A2F9E296F007A7818 /* Config.xcconfig */;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSET_CATALOG_COMPILER_OPTIMIZATION = space;
\t\t\t\tASSET_SYMBOL_GENERATION = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tDEVELOPMENT_TEAM = {TEAM_ID};
\t\t\t\tINFOPLIST_FILE = {PROJECT_NAME}/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = {PROJECT_NAME};
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {q(BUNDLE_ID)};
\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";
\t\t\t\tSUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\";
\t\t\t\tSUPPORTS_MACCATALYST = NO;
\t\t\t\tSUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
\t\t\t\tSUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = NO;
\t\t\t\tSWIFT_VERSION = 5.9;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{ids['release_target']} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbaseConfigurationReference = 8BBED19A2F9E296F007A7818 /* Config.xcconfig */;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSET_CATALOG_COMPILER_OPTIMIZATION = space;
\t\t\t\tASSET_SYMBOL_GENERATION = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tDEVELOPMENT_TEAM = {TEAM_ID};
\t\t\t\tINFOPLIST_FILE = {PROJECT_NAME}/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = {PROJECT_NAME};
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {q(BUNDLE_ID)};
\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";
\t\t\t\tSUPPORTED_PLATFORMS = \"iphoneos iphonesimulator\";
\t\t\t\tSUPPORTS_MACCATALYST = NO;
\t\t\t\tSUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO;
\t\t\t\tSUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = NO;
\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;
\t\t\t\tSWIFT_VERSION = 5.9;
\t\t\t\tTARGETED_DEVICE_FAMILY = 1;
\t\t\t\tVALIDATE_PRODUCT = YES;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{ids['debug_project']} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tSDKROOT = iphoneos;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{ids['release_project']} /* Release */ = {{
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
\t\t{ids['config_list_project']} /* Build configuration list for PBXProject \"{PROJECT_NAME}\" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{ids['debug_project']} /* Debug */,
\t\t\t\t{ids['release_project']} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{ids['config_list_target']} /* Build configuration list for PBXNativeTarget \"{PROJECT_NAME}\" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{ids['debug_target']} /* Debug */,
\t\t\t\t{ids['release_target']} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */

\t}};
\trootObject = {ids['project']} /* Project object */;
}}
"""
    return project_text, ids["target"]


def xcscheme(target_id):
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeCheck="1500" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="{PROJECT_NAME}.app" BlueprintName="{PROJECT_NAME}" ReferencedContainer="container:{PROJECT_NAME}.xcodeproj"/>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
      <Testables/>
   </TestAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="{PROJECT_NAME}.app" BlueprintName="{PROJECT_NAME}" ReferencedContainer="container:{PROJECT_NAME}.xcodeproj"/>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target_id}" BuildableName="{PROJECT_NAME}.app" BlueprintName="{PROJECT_NAME}" ReferencedContainer="container:{PROJECT_NAME}.xcodeproj"/>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration="Debug"/>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
"""


def main():
    base = pathlib.Path(__file__).resolve().parent
    files = swift_files(base)
    project_text, target_id = pbxproj(files)

    project_dir = base / f"{PROJECT_NAME}.xcodeproj"
    project_dir.mkdir(exist_ok=True)
    (project_dir / "project.pbxproj").write_text(project_text)

    scheme_dir = project_dir / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    (scheme_dir / f"{PROJECT_NAME}.xcscheme").write_text(xcscheme(target_id))

    print(f"Generated project with {len(files)} Swift files")


if __name__ == "__main__":
    main()
