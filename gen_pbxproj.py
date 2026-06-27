#!/usr/bin/env python3
"""Generate a valid Xcode 14 (objectVersion 56) project.pbxproj for Recaply.

Walks Recaply/ for .swift sources + resources and RecaplyTests/ for unit-test
sources, then emits PBXBuildFile / PBXFileReference / PBXGroup / build phases,
an app target (com.apple.product-type.application) and a unit-test target
(com.apple.product-type.bundle) wired to it via a PBXTargetDependency.

System frameworks ONLY — there are NO SPM / package references anywhere.
Deterministic md5-based IDs so re-runs are byte-stable. Adapted from the
NovelDex generator (SPM/Firebase/ZIPFoundation removed, test target + .mlmodel
added, bundle discovery made dynamic).
"""
import os
import hashlib

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "Recaply")
TESTS = os.path.join(ROOT, "RecaplyTests")
TARGET = "Recaply"
TEST_TARGET = "RecaplyTests"
BUNDLE_ID = "cn.edu.njxzc.Recaply"
TEST_BUNDLE_ID = "cn.edu.njxzc.RecaplyTests"


def oid(*parts):
    h = hashlib.md5(("::".join(parts)).encode()).hexdigest().upper()
    return h[:24]


# ---- Collect files ----
swift_files = []        # (relpath_from_Recaply, abspath)
test_swift_files = []   # (relpath_from_RecaplyTests, abspath)
resource_files = []     # (relpath_from_Recaply, abspath, kind)
bundle_resources = []   # (relpath_from_Recaply, abspath, kind)

for dirpath, dirnames, filenames in os.walk(SRC):
    # Collect bundle-like directories (Assets.xcassets, *.xcdatamodeld) and prune
    # them so we do not descend into their contents.
    keep = []
    for d in dirnames:
        full = os.path.join(dirpath, d)
        rel = os.path.relpath(full, SRC)
        if d.endswith(".xcassets"):
            bundle_resources.append((rel, full, "assetcatalog"))
        elif d.endswith(".xcdatamodeld"):
            bundle_resources.append((rel, full, "datamodel"))
        else:
            keep.append(d)
    dirnames[:] = keep
    for f in sorted(filenames):
        abspath = os.path.join(dirpath, f)
        rel = os.path.relpath(abspath, SRC)
        if f.endswith(".swift"):
            swift_files.append((rel, abspath))
        elif f == "Info.plist":
            pass  # referenced via INFOPLIST_FILE, never a build resource
        elif f.endswith(".mlmodel"):
            resource_files.append((rel, abspath, "mlmodel"))
        elif f == ".env":
            resource_files.append((rel, abspath, "env"))
        elif f.endswith(".json"):
            resource_files.append((rel, abspath, "json"))
        elif f.endswith(".plist"):
            resource_files.append((rel, abspath, "plist"))

for dirpath, dirnames, filenames in os.walk(TESTS):
    for f in sorted(filenames):
        if f.endswith(".swift"):
            abspath = os.path.join(dirpath, f)
            rel = os.path.relpath(abspath, TESTS)
            test_swift_files.append((rel, abspath))

swift_files.sort()
resource_files.sort()
bundle_resources.sort()
test_swift_files.sort()

res_all = resource_files + bundle_resources

print(f"swift={len(swift_files)} resources={len(resource_files)} bundles={len(bundle_resources)}")


# ---- File type + IDs ----
def file_type(rel):
    if rel.endswith(".swift"): return "sourcecode.swift"
    if rel.endswith(".json"): return "text.json"
    if rel.endswith(".plist"): return "text.plist.xml"
    if rel.endswith(".mlmodel"): return "file.mlmodel"
    if rel.endswith(".xcassets"): return "folder.assetcatalog"
    if rel.endswith(".xcdatamodeld"): return "wrapper.xcdatamodel"
    return "text"

src_ids = {rel: (oid("ref", rel), oid("build", rel)) for rel, _ in swift_files}
res_ids = {rel: (oid("ref", rel), oid("build", rel)) for rel, _, _ in res_all}
test_ids = {rel: (oid("testref", rel), oid("testbuild", rel)) for rel, _ in test_swift_files}

PROJECT = oid("project")
MAIN_GROUP = oid("group", "main")
PRODUCTS_GROUP = oid("group", "products")
APP_GROUP = oid("group", TARGET)
TESTS_GROUP = oid("group", TEST_TARGET)

TARGET_ID = oid("target")
TEST_TARGET_ID = oid("testtarget")
PRODUCT_REF = oid("product", "app")
TEST_PRODUCT_REF = oid("product", "test")

SOURCES_PHASE = oid("phase", "sources")
FRAMEWORKS_PHASE = oid("phase", "frameworks")
RESOURCES_PHASE = oid("phase", "resources")
TEST_SOURCES_PHASE = oid("phase", "testsources")
TEST_FRAMEWORKS_PHASE = oid("phase", "testframeworks")
TEST_RESOURCES_PHASE = oid("phase", "testresources")

TEST_PROXY = oid("proxy", "test")
TEST_DEP = oid("dep", "test")

BUILD_CONFIG_LIST_PROJ = oid("bcl", "proj")
BUILD_CONFIG_LIST_TGT = oid("bcl", "tgt")
BUILD_CONFIG_LIST_TEST = oid("bcl", "test")
DEBUG_PROJ = oid("bc", "debug-proj")
RELEASE_PROJ = oid("bc", "release-proj")
DEBUG_TGT = oid("bc", "debug-tgt")
RELEASE_TGT = oid("bc", "release-tgt")
DEBUG_TEST = oid("bc", "debug-test")
RELEASE_TEST = oid("bc", "release-test")

INFO_REF = oid("ref", "Info.plist")


def emit_build_files(L):
    L.append("\n/* Begin PBXBuildFile section */")
    for rel, _ in swift_files:
        ref, bld = src_ids[rel]
        name = os.path.basename(rel)
        L.append(f"\t\t{bld} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};")
    for rel, _, _ in res_all:
        ref, bld = res_ids[rel]
        name = os.path.basename(rel)
        phase_name = "Sources" if rel.endswith(".xcdatamodeld") else "Resources"
        L.append(f"\t\t{bld} /* {name} in {phase_name} */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};")
    for rel, _ in test_swift_files:
        ref, bld = test_ids[rel]
        name = os.path.basename(rel)
        L.append(f"\t\t{bld} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};")
    L.append("/* End PBXBuildFile section */")
    return L


def emit_file_refs(L):
    L.append("\n/* Begin PBXFileReference section */")
    L.append(f"\t\t{PRODUCT_REF} /* {TARGET}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {TARGET}.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    L.append(f"\t\t{TEST_PRODUCT_REF} /* {TEST_TARGET}.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = {TEST_TARGET}.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};")
    for rel, _ in swift_files:
        ref, _ = src_ids[rel]
        name = os.path.basename(rel)
        L.append(f"\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"{name}\"; sourceTree = \"<group>\"; }};")
    for rel, _, _ in res_all:
        ref, _ = res_ids[rel]
        name = os.path.basename(rel)
        ft = file_type(rel)
        L.append(f"\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ft}; path = \"{name}\"; sourceTree = \"<group>\"; }};")
    for rel, _ in test_swift_files:
        ref, _ = test_ids[rel]
        name = os.path.basename(rel)
        L.append(f"\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = \"{name}\"; sourceTree = \"<group>\"; }};")
    L.append(f"\t\t{INFO_REF} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};")
    L.append("/* End PBXFileReference section */")
    return L


def emit_groups(L):
    tree = {}

    def insert(rel, ref):
        parts = rel.split("/")
        node = tree
        for p in parts[:-1]:
            node = node.setdefault(("dir", p), {})
        node[("file", parts[-1])] = ref

    for rel, _ in swift_files:
        insert(rel, src_ids[rel][0])
    for rel, _, _ in res_all:
        insert(rel, res_ids[rel][0])
    # Place Info.plist under the Resources group so its <group> reference resolves
    # to Recaply/Resources/Info.plist (the build still finds it via INFOPLIST_FILE).
    insert("Resources/Info.plist", INFO_REF)

    def gid(path):
        return oid("group", path)

    def nm_for(path):
        return path.split("/")[-1]

    def emit_group(node, path, group_id, name, is_root=False):
        L.append(f"\t\t{group_id} /* {name} */ = {{")
        L.append("\t\t\tisa = PBXGroup;")
        L.append("\t\t\tchildren = (")
        for key in sorted(node.keys(), key=lambda k: (k[0] != "dir", k[1])):
            kind, nm = key
            if kind == "dir":
                child_path = f"{path}/{nm}" if path else nm
                L.append(f"\t\t\t\t{gid(child_path)} /* {nm} */,")
            else:
                L.append(f"\t\t\t\t{node[key]} /* {nm} */,")
        L.append("\t\t\t);")
        if is_root:
            L.append(f"\t\t\tpath = {name};")
        else:
            L.append(f"\t\t\tpath = {nm_for(path)};")
        L.append("\t\t\tsourceTree = \"<group>\";")
        L.append("\t\t};")
        for key in node:
            if key[0] == "dir":
                child_path = f"{path}/{key[1]}" if path else key[1]
                emit_group(node[key], child_path, gid(child_path), key[1])

    L.append("\n/* Begin PBXGroup section */")
    # main group
    L.append(f"\t\t{MAIN_GROUP} = {{")
    L.append("\t\t\tisa = PBXGroup;")
    L.append("\t\t\tchildren = (")
    L.append(f"\t\t\t\t{APP_GROUP} /* {TARGET} */,")
    L.append(f"\t\t\t\t{TESTS_GROUP} /* {TEST_TARGET} */,")
    L.append(f"\t\t\t\t{PRODUCTS_GROUP} /* Products */,")
    L.append("\t\t\t);")
    L.append("\t\t\tsourceTree = \"<group>\";")
    L.append("\t\t};")
    # products group
    L.append(f"\t\t{PRODUCTS_GROUP} /* Products */ = {{")
    L.append("\t\t\tisa = PBXGroup;")
    L.append("\t\t\tchildren = (")
    L.append(f"\t\t\t\t{PRODUCT_REF} /* {TARGET}.app */,")
    L.append(f"\t\t\t\t{TEST_PRODUCT_REF} /* {TEST_TARGET}.xctest */,")
    L.append("\t\t\t);")
    L.append("\t\t\tname = Products;")
    L.append("\t\t\tsourceTree = \"<group>\";")
    L.append("\t\t};")
    # app group (nested tree mirroring disk layout)
    emit_group(tree, "", APP_GROUP, TARGET, is_root=True)
    # tests group (flat)
    L.append(f"\t\t{TESTS_GROUP} /* {TEST_TARGET} */ = {{")
    L.append("\t\t\tisa = PBXGroup;")
    L.append("\t\t\tchildren = (")
    for rel, _ in test_swift_files:
        ref, _ = test_ids[rel]
        name = os.path.basename(rel)
        L.append(f"\t\t\t\t{ref} /* {name} */,")
    L.append("\t\t\t);")
    L.append(f"\t\t\tpath = {TEST_TARGET};")
    L.append("\t\t\tsourceTree = \"<group>\";")
    L.append("\t\t};")
    L.append("/* End PBXGroup section */")
    return L


def emit_phases(L):
    # Frameworks build phases (app + test, both empty: system frameworks only)
    L.append("\n/* Begin PBXFrameworksBuildPhase section */")
    for ph in [FRAMEWORKS_PHASE, TEST_FRAMEWORKS_PHASE]:
        L.append(f"\t\t{ph} /* Frameworks */ = {{")
        L.append("\t\t\tisa = PBXFrameworksBuildPhase;")
        L.append("\t\t\tbuildActionMask = 2147483647;")
        L.append("\t\t\tfiles = (")
        L.append("\t\t\t);")
        L.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        L.append("\t\t};")
    L.append("/* End PBXFrameworksBuildPhase section */")

    # Sources build phases (app sources + test sources)
    L.append("\n/* Begin PBXSourcesBuildPhase section */")
    for ph, files, ids in [
        (SOURCES_PHASE, swift_files, src_ids),
        (TEST_SOURCES_PHASE, test_swift_files, test_ids),
    ]:
        L.append(f"\t\t{ph} /* Sources */ = {{")
        L.append("\t\t\tisa = PBXSourcesBuildPhase;")
        L.append("\t\t\tbuildActionMask = 2147483647;")
        L.append("\t\t\tfiles = (")
        for rel, _ in files:
            _, bld = ids[rel]
            L.append(f"\t\t\t\t{bld} /* {os.path.basename(rel)} in Sources */,")
        if ph == SOURCES_PHASE:
            for rel, _, kind in res_all:
                if kind == "datamodel":
                    _, bld = res_ids[rel]
                    L.append(f"\t\t\t\t{bld} /* {os.path.basename(rel)} in Sources */,")
        L.append("\t\t\t);")
        L.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        L.append("\t\t};")
    L.append("/* End PBXSourcesBuildPhase section */")

    # Resources build phases (app populated, test empty)
    L.append("\n/* Begin PBXResourcesBuildPhase section */")
    L.append(f"\t\t{RESOURCES_PHASE} /* Resources */ = {{")
    L.append("\t\t\tisa = PBXResourcesBuildPhase;")
    L.append("\t\t\tbuildActionMask = 2147483647;")
    L.append("\t\t\tfiles = (")
    for rel, _, kind in res_all:
        if kind == "datamodel":
            continue
        _, bld = res_ids[rel]
        L.append(f"\t\t\t\t{bld} /* {os.path.basename(rel)} in Resources */,")
    L.append("\t\t\t);")
    L.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    L.append("\t\t};")
    L.append(f"\t\t{TEST_RESOURCES_PHASE} /* Resources */ = {{")
    L.append("\t\t\tisa = PBXResourcesBuildPhase;")
    L.append("\t\t\tbuildActionMask = 2147483647;")
    L.append("\t\t\tfiles = (")
    L.append("\t\t\t);")
    L.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    L.append("\t\t};")
    L.append("/* End PBXResourcesBuildPhase section */")
    return L


def emit_targets_and_deps(L):
    L.append("\n/* Begin PBXNativeTarget section */")
    # App target
    L.append(f"\t\t{TARGET_ID} /* {TARGET} */ = {{")
    L.append("\t\t\tisa = PBXNativeTarget;")
    L.append(f"\t\t\tbuildConfigurationList = {BUILD_CONFIG_LIST_TGT} /* Build configuration list for PBXNativeTarget \"{TARGET}\" */;")
    L.append("\t\t\tbuildPhases = (")
    L.append(f"\t\t\t\t{SOURCES_PHASE} /* Sources */,")
    L.append(f"\t\t\t\t{FRAMEWORKS_PHASE} /* Frameworks */,")
    L.append(f"\t\t\t\t{RESOURCES_PHASE} /* Resources */,")
    L.append("\t\t\t);")
    L.append("\t\t\tbuildRules = (")
    L.append("\t\t\t);")
    L.append("\t\t\tdependencies = (")
    L.append("\t\t\t);")
    L.append(f"\t\t\tname = {TARGET};")
    L.append(f"\t\t\tproductName = {TARGET};")
    L.append(f"\t\t\tproductReference = {PRODUCT_REF} /* {TARGET}.app */;")
    L.append("\t\t\tproductType = \"com.apple.product-type.application\";")
    L.append("\t\t};")
    # Test target
    L.append(f"\t\t{TEST_TARGET_ID} /* {TEST_TARGET} */ = {{")
    L.append("\t\t\tisa = PBXNativeTarget;")
    L.append(f"\t\t\tbuildConfigurationList = {BUILD_CONFIG_LIST_TEST} /* Build configuration list for PBXNativeTarget \"{TEST_TARGET}\" */;")
    L.append("\t\t\tbuildPhases = (")
    L.append(f"\t\t\t\t{TEST_SOURCES_PHASE} /* Sources */,")
    L.append(f"\t\t\t\t{TEST_FRAMEWORKS_PHASE} /* Frameworks */,")
    L.append(f"\t\t\t\t{TEST_RESOURCES_PHASE} /* Resources */,")
    L.append("\t\t\t);")
    L.append("\t\t\tbuildRules = (")
    L.append("\t\t\t);")
    L.append("\t\t\tdependencies = (")
    L.append(f"\t\t\t\t{TEST_DEP} /* PBXTargetDependency */,")
    L.append("\t\t\t);")
    L.append(f"\t\t\tname = {TEST_TARGET};")
    L.append(f"\t\t\tproductName = {TEST_TARGET};")
    L.append(f"\t\t\tproductReference = {TEST_PRODUCT_REF} /* {TEST_TARGET}.xctest */;")
    L.append("\t\t\tproductType = \"com.apple.product-type.bundle.unit-test\";")
    L.append("\t\t};")
    L.append("/* End PBXNativeTarget section */")

    # PBXContainerItemProxy (test -> app)
    L.append("\n/* Begin PBXContainerItemProxy section */")
    L.append(f"\t\t{TEST_PROXY} /* PBXContainerItemProxy */ = {{")
    L.append("\t\t\tisa = PBXContainerItemProxy;")
    L.append(f"\t\t\tcontainerPortal = {PROJECT} /* Project object */;")
    L.append("\t\t\tproxyType = 1;")
    L.append(f"\t\t\tremoteGlobalIDString = {TARGET_ID};")
    L.append(f"\t\t\tremoteInfo = {TARGET};")
    L.append("\t\t};")
    L.append("/* End PBXContainerItemProxy section */")

    # PBXTargetDependency
    L.append("\n/* Begin PBXTargetDependency section */")
    L.append(f"\t\t{TEST_DEP} /* PBXTargetDependency */ = {{")
    L.append("\t\t\tisa = PBXTargetDependency;")
    L.append(f"\t\t\ttarget = {TARGET_ID} /* {TARGET} */;")
    L.append(f"\t\t\ttargetProxy = {TEST_PROXY} /* PBXContainerItemProxy */;")
    L.append("\t\t};")
    L.append("/* End PBXTargetDependency section */")
    return L


COMMON_BUILD = """\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ANALYZER_NONNULL = YES;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu11;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.4;
\t\t\t\tMTL_FAST_MATH = YES;
\t\t\t\tSDKROOT = iphoneos;"""

TARGET_BUILD = f"""\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = {TARGET}/Resources/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {BUNDLE_ID};
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";"""

TEST_BUILD = f"""\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = "";
\t\t\t\tENABLE_TESTING_SEARCH_PATHS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@loader_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = {TEST_BUNDLE_ID};
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = NO;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/{TARGET}.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/{TARGET}";"""


def emit_configs(L):
    L.append("\n/* Begin XCBuildConfiguration section */")
    proj_configs = [
        (DEBUG_PROJ, "Debug", "\t\t\t\tONLY_ACTIVE_ARCH = YES;\n\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";\n\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;\n\t\t\t\tENABLE_TESTABILITY = YES;\n\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;"),
        (RELEASE_PROJ, "Release", "\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";\n\t\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";\n\t\t\t\tENABLE_NS_ASSERTIONS = NO;\n\t\t\t\tVALIDATE_PRODUCT = YES;"),
    ]
    for cid, name, extra in proj_configs:
        L.append(f"\t\t{cid} /* {name} */ = {{")
        L.append("\t\t\tisa = XCBuildConfiguration;")
        L.append("\t\t\tbuildSettings = {")
        L.append(COMMON_BUILD)
        L.append(extra)
        L.append("\t\t\t};")
        L.append(f"\t\t\tname = {name};")
        L.append("\t\t};")
    for cid, name in [(DEBUG_TGT, "Debug"), (RELEASE_TGT, "Release")]:
        L.append(f"\t\t{cid} /* {name} */ = {{")
        L.append("\t\t\tisa = XCBuildConfiguration;")
        L.append("\t\t\tbuildSettings = {")
        L.append(TARGET_BUILD)
        L.append("\t\t\t};")
        L.append(f"\t\t\tname = {name};")
        L.append("\t\t};")
    for cid, name in [(DEBUG_TEST, "Debug"), (RELEASE_TEST, "Release")]:
        L.append(f"\t\t{cid} /* {name} */ = {{")
        L.append("\t\t\tisa = XCBuildConfiguration;")
        L.append("\t\t\tbuildSettings = {")
        L.append(TEST_BUILD)
        L.append("\t\t\t};")
        L.append(f"\t\t\tname = {name};")
        L.append("\t\t};")
    L.append("/* End XCBuildConfiguration section */")

    L.append("\n/* Begin XCConfigurationList section */")
    L.append(f"\t\t{BUILD_CONFIG_LIST_PROJ} /* Build configuration list for PBXProject */ = {{")
    L.append("\t\t\tisa = XCConfigurationList;")
    L.append("\t\t\tbuildConfigurations = (")
    L.append(f"\t\t\t\t{DEBUG_PROJ} /* Debug */,")
    L.append(f"\t\t\t\t{RELEASE_PROJ} /* Release */,")
    L.append("\t\t\t);")
    L.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    L.append("\t\t\tdefaultConfigurationName = Release;")
    L.append("\t\t};")
    L.append(f"\t\t{BUILD_CONFIG_LIST_TGT} /* Build configuration list for PBXNativeTarget \"{TARGET}\" */ = {{")
    L.append("\t\t\tisa = XCConfigurationList;")
    L.append("\t\t\tbuildConfigurations = (")
    L.append(f"\t\t\t\t{DEBUG_TGT} /* Debug */,")
    L.append(f"\t\t\t\t{RELEASE_TGT} /* Release */,")
    L.append("\t\t\t);")
    L.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    L.append("\t\t\tdefaultConfigurationName = Release;")
    L.append("\t\t};")
    L.append(f"\t\t{BUILD_CONFIG_LIST_TEST} /* Build configuration list for PBXNativeTarget \"{TEST_TARGET}\" */ = {{")
    L.append("\t\t\tisa = XCConfigurationList;")
    L.append("\t\t\tbuildConfigurations = (")
    L.append(f"\t\t\t\t{DEBUG_TEST} /* Debug */,")
    L.append(f"\t\t\t\t{RELEASE_TEST} /* Release */,")
    L.append("\t\t\t);")
    L.append("\t\t\tdefaultConfigurationIsVisible = 0;")
    L.append("\t\t\tdefaultConfigurationName = Release;")
    L.append("\t\t};")
    L.append("/* End XCConfigurationList section */")
    return L


def emit_project(L):
    L.append("\n/* Begin PBXProject section */")
    L.append(f"\t\t{PROJECT} /* Project object */ = {{")
    L.append("\t\t\tisa = PBXProject;")
    L.append("\t\t\tattributes = {")
    L.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    L.append("\t\t\t\tLastSwiftUpdateCheck = 1430;")
    L.append("\t\t\t\tLastUpgradeCheck = 1430;")
    L.append("\t\t\t\tTargetAttributes = {")
    L.append(f"\t\t\t\t\t{TARGET_ID} = {{")
    L.append("\t\t\t\t\t\tCreatedOnToolsVersion = 14.3;")
    L.append("\t\t\t\t\t};")
    L.append(f"\t\t\t\t\t{TEST_TARGET_ID} = {{")
    L.append("\t\t\t\t\t\tCreatedOnToolsVersion = 14.3;")
    L.append(f"\t\t\t\t\t\tTestTargetID = {TARGET_ID} /* {TARGET} */;")
    L.append("\t\t\t\t\t};")
    L.append("\t\t\t\t};")
    L.append("\t\t\t};")
    L.append(f"\t\t\tbuildConfigurationList = {BUILD_CONFIG_LIST_PROJ} /* Build configuration list for PBXProject */;")
    L.append("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
    L.append("\t\t\tdevelopmentRegion = en;")
    L.append("\t\t\thasScannedForEncodings = 0;")
    L.append("\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);")
    L.append(f"\t\t\tmainGroup = {MAIN_GROUP};")
    L.append(f"\t\t\tproductRefGroup = {PRODUCTS_GROUP} /* Products */;")
    L.append("\t\t\tprojectDirPath = \"\";")
    L.append("\t\t\tprojectRoot = \"\";")
    L.append("\t\t\ttargets = (")
    L.append(f"\t\t\t\t{TARGET_ID} /* {TARGET} */,")
    L.append(f"\t\t\t\t{TEST_TARGET_ID} /* {TEST_TARGET} */,")
    L.append("\t\t\t);")
    L.append("\t\t};")
    L.append("/* End PBXProject section */")
    L.append("\t};")
    L.append(f"\trootObject = {PROJECT} /* Project object */;")
    L.append("}")
    return L


def main():
    L = []
    L.append("// !$*UTF8*$!")
    L.append("{")
    L.append("\tarchiveVersion = 1;")
    L.append("\tclasses = {")
    L.append("\t};")
    L.append("\tobjectVersion = 56;")
    L.append("\tobjects = {")
    L = emit_build_files(L)
    L = emit_file_refs(L)
    L = emit_groups(L)
    L = emit_phases(L)
    L = emit_targets_and_deps(L)
    L = emit_configs(L)
    L = emit_project(L)
    out_dir = os.path.join(ROOT, f"{TARGET}.xcodeproj")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "project.pbxproj")
    with open(out, "w") as f:
        f.write("\n".join(L) + "\n")
    print(f"WROTE {out} ({len(L)} lines)")


if __name__ == "__main__":
    main()
