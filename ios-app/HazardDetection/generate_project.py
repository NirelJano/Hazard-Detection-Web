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
    # build file refs
    "bfApp":            uid(),
    "bfContent":        uid(),
    "bfCameraManager":  uid(),
    "bfCameraView":     uid(),
    # product
    "productFile":      uid(),
    # CoreML Model
    "fileModel":        uid(),
    "bfModel":          uid(),
    "fileModelC":       uid(),
    "bfModelC":         uid(),
    "filePng1":         uid(),
    "bfPng1":           uid(),
    "filePng2":         uid(),
    "bfPng2":           uid(),
    "filePng3":         uid(),
    "bfPng3":           uid(),
    "fileDesign":       uid(),
    "bfDesign":         uid(),
    "fileLiveDetection":uid(),
    "bfLiveDetection":  uid(),
    "fileHome":          uid(),
    "bfHome":            uid(),
    "fileBackend":       uid(),
    "bfBackend":         uid(),
}

SWIFT_FILES = [
    ("HazardDetectionApp.swift", "fileApp",           "bfApp"),
    ("ContentView.swift",        "fileContent",        "bfContent"),
    ("CameraManager.swift",      "fileCameraManager",  "bfCameraManager"),
    ("CameraView.swift",         "fileCameraView",     "bfCameraView"),
    ("DesignSystem.swift",       "fileDesign",         "bfDesign"),
    ("LiveDetectionView.swift",  "fileLiveDetection",  "bfLiveDetection"),
    ("HomeView.swift",           "fileHome",           "bfHome"),
    ("BackendServices.swift",    "fileBackend",        "bfBackend"),
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

    for fname, fid, _ in PNG_FILES:
        file_refs += f"""\t\t{I[fid]} /* {fname} */ = {{isa = PBXFileReference; lastKnownFileType = image.png; path = {fname}; sourceTree = "<group>"; }};\n"""

    build_files = ""
    for fname, fid, bfid in SWIFT_FILES:
        build_files += f"\t\t{I[bfid]} /* {fname} in Sources */ = {{isa = PBXBuildFile; fileRef = {I[fid]} /* {fname} */; }};\n"
    
    # Add CoreML model to build files
    build_files += f"\t\t{I['bfModel']} /* best.mlpackage in Resources */ = {{isa = PBXBuildFile; fileRef = {I['fileModel']} /* best.mlpackage */; }};\n"
    build_files += f"\t\t{I['bfModelC']} /* best.mlmodelc in Resources */ = {{isa = PBXBuildFile; fileRef = {I['fileModelC']} /* best.mlmodelc */; }};\n"

    for fname, fid, bfid in PNG_FILES:
        build_files += f"\t\t{I[bfid]} /* {fname} in Resources */ = {{isa = PBXBuildFile; fileRef = {I[fid]} /* {fname} */; }};\n"

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

/* Begin XCBuildConfiguration section */
\t\t{I['buildConfigDebug']} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSET_CATALOG_COMPILER_OPTIMIZATION = space;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tINFOPLIST_FILE = HazardDetection/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "com.hazarddetection.app";
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_VERSION = 5.9;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{I['buildConfigRel']} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tASSET_CATALOG_COMPILER_OPTIMIZATION = space;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tINFOPLIST_FILE = HazardDetection/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "com.hazarddetection.app";
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

def main():
    base = pathlib.Path(__file__).parent
    proj_dir = base / "HazardDetection.xcodeproj"
    proj_dir.mkdir(exist_ok=True)

    pbx_path = proj_dir / "project.pbxproj"
    pbx_path.write_text(pbxproj())
    print(f"✅  Generated: {pbx_path}")
    print("👉  Open with: open HazardDetection.xcodeproj")

if __name__ == "__main__":
    main()
