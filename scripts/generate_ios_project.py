#!/usr/bin/env python3
import os
import sys

def main():
    proj_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "Apps", "iOS", "PrivateIndex.xcodeproj"))
    os.makedirs(proj_dir, exist_ok=True)
    pbxproj_path = os.path.join(proj_dir, "project.pbxproj")

    # IDs for objects
    P_APP_SWIFT_BF = "010000010000000100000001"
    P_APP_SWIFT_FR = "010000010000000100000002"

    P_STATE_SWIFT_BF = "010000010000000200000001"
    P_STATE_SWIFT_FR = "010000010000000200000002"

    P_CONT_SWIFT_BF = "010000010000000300000001"
    P_CONT_SWIFT_FR = "010000010000000300000002"

    P_MAIN_SWIFT_BF = "010000010000000400000001"
    P_MAIN_SWIFT_FR = "010000010000000400000002"

    P_SEARCH_SWIFT_BF = "010000010000000500000001"
    P_SEARCH_SWIFT_FR = "010000010000000500000002"

    P_DOCS_SWIFT_BF = "010000010000000600000001"
    P_DOCS_SWIFT_FR = "010000010000000600000002"

    P_SETT_SWIFT_BF = "010000010000000700000001"
    P_SETT_SWIFT_FR = "010000010000000700000002"

    P_ASSETS_BF = "010000010000000800000001"
    P_ASSETS_FR = "010000010000000800000002"

    P_INFOPLIST_FR = "010000010000000900000002"

    P_ENGINE_PKG_REF = "010000020000000100000001"
    P_ENGINE_PROD_DEP = "010000020000000100000002"
    P_ENGINE_BF = "010000020000000100000003"

    P_APP_PRODUCT_FR = "010000030000000100000001"

    P_TARGET = "010000040000000100000001"
    P_PROJECT = "010000050000000100000001"

    P_MAIN_GROUP = "010000060000000100000001"
    P_SOURCES_GROUP = "010000060000000100000002"
    P_MODELS_GROUP = "010000060000000100000003"
    P_SERVICES_GROUP = "010000060000000100000004"
    P_VIEWS_GROUP = "010000060000000100000005"
    P_PRODUCTS_GROUP = "010000060000000100000006"
    P_FRAMEWORKS_GROUP = "010000060000000100000007"

    P_SOURCES_BUILD_PHASE = "010000070000000100000001"
    P_FRAMEWORKS_BUILD_PHASE = "010000070000000100000002"
    P_RESOURCES_BUILD_PHASE = "010000070000000100000003"

    P_PROJ_CFG_LIST = "010000080000000100000001"
    P_PROJ_CFG_DEBUG = "010000080000000100000002"
    P_PROJ_CFG_RELEASE = "010000080000000100000003"

    P_TGT_CFG_LIST = "010000080000000200000001"
    P_TGT_CFG_DEBUG = "010000080000000200000002"
    P_TGT_CFG_RELEASE = "010000080000000200000003"

    content = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
		{P_APP_SWIFT_BF} /* PrivateIndexIOSApp.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {P_APP_SWIFT_FR} /* PrivateIndexIOSApp.swift */; }};
		{P_STATE_SWIFT_BF} /* IOSAppState.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {P_STATE_SWIFT_FR} /* IOSAppState.swift */; }};
		{P_CONT_SWIFT_BF} /* IOSContainerManager.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {P_CONT_SWIFT_FR} /* IOSContainerManager.swift */; }};
		{P_MAIN_SWIFT_BF} /* MainTabView.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {P_MAIN_SWIFT_FR} /* MainTabView.swift */; }};
		{P_SEARCH_SWIFT_BF} /* IOSSearchView.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {P_SEARCH_SWIFT_FR} /* IOSSearchView.swift */; }};
		{P_DOCS_SWIFT_BF} /* IOSDocumentsView.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {P_DOCS_SWIFT_FR} /* IOSDocumentsView.swift */; }};
		{P_SETT_SWIFT_BF} /* IOSSettingsView.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {P_SETT_SWIFT_FR} /* IOSSettingsView.swift */; }};
		{P_ASSETS_BF} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {P_ASSETS_FR} /* Assets.xcassets */; }};
		{P_ENGINE_BF} /* PrivateIndexEngine in Frameworks */ = {{isa = PBXBuildFile; productRef = {P_ENGINE_PROD_DEP} /* PrivateIndexEngine */; }};
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		{P_APP_PRODUCT_FR} /* PrivateIndex.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = PrivateIndex.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{P_APP_SWIFT_FR} /* PrivateIndexIOSApp.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PrivateIndexIOSApp.swift; sourceTree = "<group>"; }};
		{P_STATE_SWIFT_FR} /* IOSAppState.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = IOSAppState.swift; sourceTree = "<group>"; }};
		{P_CONT_SWIFT_FR} /* IOSContainerManager.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = IOSContainerManager.swift; sourceTree = "<group>"; }};
		{P_MAIN_SWIFT_FR} /* MainTabView.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MainTabView.swift; sourceTree = "<group>"; }};
		{P_SEARCH_SWIFT_FR} /* IOSSearchView.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = IOSSearchView.swift; sourceTree = "<group>"; }};
		{P_DOCS_SWIFT_FR} /* IOSDocumentsView.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = IOSDocumentsView.swift; sourceTree = "<group>"; }};
		{P_SETT_SWIFT_FR} /* IOSSettingsView.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = IOSSettingsView.swift; sourceTree = "<group>"; }};
		{P_ASSETS_FR} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};
		{P_INFOPLIST_FR} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{P_FRAMEWORKS_BUILD_PHASE} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{P_ENGINE_BF} /* PrivateIndexEngine in Frameworks */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{P_MAIN_GROUP} = {{
			isa = PBXGroup;
			children = (
				{P_SOURCES_GROUP} /* Sources */,
				{P_ASSETS_FR} /* Assets.xcassets */,
				{P_INFOPLIST_FR} /* Info.plist */,
				{P_PRODUCTS_GROUP} /* Products */,
				{P_FRAMEWORKS_GROUP} /* Frameworks */,
			);
			sourceTree = "<group>";
		}};
		{P_SOURCES_GROUP} /* Sources */ = {{
			isa = PBXGroup;
			children = (
				{P_APP_SWIFT_FR} /* PrivateIndexIOSApp.swift */,
				{P_MODELS_GROUP} /* Models */,
				{P_SERVICES_GROUP} /* Services */,
				{P_VIEWS_GROUP} /* Views */,
			);
			path = Sources/PrivateIndexIOS;
			sourceTree = "<group>";
		}};
		{P_MODELS_GROUP} /* Models */ = {{
			isa = PBXGroup;
			children = (
				{P_STATE_SWIFT_FR} /* IOSAppState.swift */,
			);
			path = Models;
			sourceTree = "<group>";
		}};
		{P_SERVICES_GROUP} /* Services */ = {{
			isa = PBXGroup;
			children = (
				{P_CONT_SWIFT_FR} /* IOSContainerManager.swift */,
			);
			path = Services;
			sourceTree = "<group>";
		}};
		{P_VIEWS_GROUP} /* Views */ = {{
			isa = PBXGroup;
			children = (
				{P_MAIN_SWIFT_FR} /* MainTabView.swift */,
				{P_SEARCH_SWIFT_FR} /* IOSSearchView.swift */,
				{P_DOCS_SWIFT_FR} /* IOSDocumentsView.swift */,
				{P_SETT_SWIFT_FR} /* IOSSettingsView.swift */,
			);
			path = Views;
			sourceTree = "<group>";
		}};
		{P_PRODUCTS_GROUP} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{P_APP_PRODUCT_FR} /* PrivateIndex.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
		{P_FRAMEWORKS_GROUP} /* Frameworks */ = {{
			isa = PBXGroup;
			children = (
			);
			name = Frameworks;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{P_TARGET} /* PrivateIndex */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {P_TGT_CFG_LIST} /* Build configuration list for PBXNativeTarget "PrivateIndex" */;
			buildPhases = (
				{P_SOURCES_BUILD_PHASE} /* Sources */,
				{P_FRAMEWORKS_BUILD_PHASE} /* Frameworks */,
				{P_RESOURCES_BUILD_PHASE} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = PrivateIndex;
			packageProductDependencies = (
				{P_ENGINE_PROD_DEP} /* PrivateIndexEngine */,
			);
			productName = PrivateIndex;
			productReference = {P_APP_PRODUCT_FR} /* PrivateIndex.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{P_PROJECT} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
				TargetAttributes = {{
					{P_TARGET} = {{
						CreatedOnToolsVersion = 16.0;
						DevelopmentTeam = "";
						ProvisioningStyle = Automatic;
					}};
				}};
			}};
			buildConfigurationList = {P_PROJ_CFG_LIST} /* Build configuration list for PBXProject "PrivateIndex" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {P_MAIN_GROUP};
			packageReferences = (
				{P_ENGINE_PKG_REF} /* XCLocalSwiftPackageReference "../../Packages/PrivateIndexEngine" */,
			);
			productRefGroup = {P_PRODUCTS_GROUP} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{P_TARGET} /* PrivateIndex */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{P_RESOURCES_BUILD_PHASE} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{P_ASSETS_BF} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{P_SOURCES_BUILD_PHASE} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{P_APP_SWIFT_BF} /* PrivateIndexIOSApp.swift in Sources */,
				{P_STATE_SWIFT_BF} /* IOSAppState.swift in Sources */,
				{P_CONT_SWIFT_BF} /* IOSContainerManager.swift in Sources */,
				{P_MAIN_SWIFT_BF} /* MainTabView.swift in Sources */,
				{P_SEARCH_SWIFT_BF} /* IOSSearchView.swift in Sources */,
				{P_DOCS_SWIFT_BF} /* IOSDocumentsView.swift in Sources */,
				{P_SETT_SWIFT_BF} /* IOSSettingsView.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		{P_PROJ_CFG_DEBUG} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			}};
			name = Debug;
		}};
		{P_PROJ_CFG_RELEASE} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				MTL_ENABLE_DEBUG_INFO = NO;
				MTL_FAST_MATH = YES;
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = "wholemodule";
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				VALIDATE_PRODUCT = YES;
			}};
			name = Release;
		}};
		{P_TGT_CFG_DEBUG} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.app.privateindex.ios;
				PRODUCT_NAME = "Private Index";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Debug;
		}};
		{P_TGT_CFG_RELEASE} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.app.privateindex.ios;
				PRODUCT_NAME = "Private Index";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{P_PROJ_CFG_LIST} /* Build configuration list for PBXProject "PrivateIndex" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{P_PROJ_CFG_DEBUG} /* Debug */,
				{P_PROJ_CFG_RELEASE} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{P_TGT_CFG_LIST} /* Build configuration list for PBXNativeTarget "PrivateIndex" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{P_TGT_CFG_DEBUG} /* Debug */,
				{P_TGT_CFG_RELEASE} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */

/* Begin XCLocalSwiftPackageReference section */
		{P_ENGINE_PKG_REF} /* XCLocalSwiftPackageReference "../../Packages/PrivateIndexEngine" */ = {{
			isa = XCLocalSwiftPackageReference;
			relativePath = "../../Packages/PrivateIndexEngine";
		}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCSwiftPackageProductDependency section */
		{P_ENGINE_PROD_DEP} /* PrivateIndexEngine */ = {{
			isa = XCSwiftPackageProductDependency;
			package = {P_ENGINE_PKG_REF} /* XCLocalSwiftPackageReference "../../Packages/PrivateIndexEngine" */;
			productName = PrivateIndexEngine;
		}};
/* End XCSwiftPackageProductDependency section */

	}};
	rootObject = {P_PROJECT} /* Project object */;
}}
"""
    with open(pbxproj_path, "w") as f:
        f.write(content)
    print(f"Generated: {pbxproj_path}")

if __name__ == "__main__":
    main()
