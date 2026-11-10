#[path = "src/build_target.rs"]
mod build_target;

fn main() {
    // In build.rs, `#[cfg(target_os)]` tests the build-script host, not
    // Cargo's target platform. Prefer Cargo's target OS; fall back to parsing
    // TARGET for old toolchains missing the variable, so cross-compiling
    // armv7 Android from a Linux host does not link desktop runtime libraries.
    let target = std::env::var("TARGET").unwrap_or_default();
    let target_os = build_target::classify_target_os(
        &target,
        std::env::var("CARGO_CFG_TARGET_OS").ok().as_deref(),
    );
    println!("cargo:warning=OpenLess build target={target}, target_os={target_os}");
    if target_os == "windows" {
        link_windows_common_controls_v6_manifest_dependency();
    }
    if target_os == "macos" {
        // Apple system recognition is independent of downloadable model runtimes.
        println!("cargo:rustc-link-lib=framework=Speech");
        link_macos_compiler_runtime();
        build_meeting_media();
        let target_arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap_or_default();
        if target_arch == "aarch64" {
            build_experimental_gemma();
        }
    }

    if target_os == "android" {
        link_android_cpp_runtime();
    }

    // `local_asr_sherpa`: targets that link sherpa-onnx for local ASR —
    // Windows, and arm64 Android (see the Cargo.toml dependency comment).
    // classify_target_os() only names android/macos/linux, so Windows is
    // read from Cargo's own variable.
    println!("cargo::rustc-check-cfg=cfg(local_asr_sherpa)");
    let cargo_target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let target_arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap_or_default();
    if cargo_target_os == "windows" || (target_os == "android" && target_arch == "aarch64") {
        println!("cargo:rustc-cfg=local_asr_sherpa");
    }

    tauri_build::build();
}

fn build_meeting_media() {
    let root = std::path::PathBuf::from(std::env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let out = std::path::PathBuf::from(std::env::var_os("OUT_DIR").unwrap());
    let arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap();
    let swift_arch = if arch == "aarch64" { "arm64" } else { "x86_64" };
    for path in ["Package.swift", "Package.resolved", "src/meetings", "vendor/webrtc-aec3"] {
        println!("cargo:rerun-if-changed={path}");
    }
    println!("cargo:rerun-if-env-changed=OPENLESS_MEETING_SWIFT_SCRATCH");
    let scratch = std::env::var_os("OPENLESS_MEETING_SWIFT_SCRATCH")
        .map(std::path::PathBuf::from).unwrap_or_else(|| out.join("meeting-runtime"));
    let cache = scratch.join("compiler-cache");
    // Optional local source checkout for offline development. Production uses this package's
    // pinned remote graph. Both paths compile Swift sources rather than accepting prebuilt code.
    println!("cargo:rerun-if-env-changed=OPENLESS_MEETING_SWIFT_PACKAGE");
    println!("cargo:rerun-if-env-changed=OPENLESS_SWIFTPM_DISABLE_SANDBOX");
    println!("cargo:rerun-if-env-changed=OPENLESS_SWIFTPM_BUILD_SYSTEM");
    let package = std::env::var_os("OPENLESS_MEETING_SWIFT_PACKAGE")
        .map(std::path::PathBuf::from).unwrap_or_else(|| root.clone());
    let command = || {
        let mut command = std::process::Command::new("xcrun");
        command.args(["swift", "build", "--package-path"]).arg(&package)
            .arg("--scratch-path").arg(&scratch)
            .arg("--cache-path").arg(cache.join("packages"))
            .arg("--config-path").arg(cache.join("config"))
            .arg("--security-path").arg(cache.join("security"))
            .args(["--configuration", "release", "--product", "OpenLessMeetings", "-j", "4", "--triple"])
            .arg(format!("{swift_arch}-apple-macosx14.0"))
            .env("SWIFTPM_MODULECACHE_OVERRIDE", cache.join("modules"))
            .env("CLANG_MODULE_CACHE_PATH", cache.join("clang"));
        if std::env::var_os("OPENLESS_SWIFTPM_DISABLE_SANDBOX").as_deref() == Some(std::ffi::OsStr::new("1")) {
            // Disables only SwiftPM's nested build sandbox; the invoking environment's
            // filesystem/network permissions continue to apply to every compiler process.
            command.arg("--disable-sandbox");
        }
        if let Some(system) = std::env::var_os("OPENLESS_SWIFTPM_BUILD_SYSTEM") {
            command.arg("--build-system").arg(system);
        }
        command
    };
    assert!(command().status().expect("SwiftPM is required for local meetings").success(),
        "meeting runtime failed to compile");
    let output = command().arg("--show-bin-path").output().expect("SwiftPM product path");
    assert!(output.status.success(), "SwiftPM product path is unavailable");
    let products = std::path::PathBuf::from(String::from_utf8(output.stdout).unwrap().trim());
    assert!(products.join("libOpenLessMeetings.a").is_file(), "meeting static library is missing");
    let resources = root.join("target/meeting-runtime-resources");
    std::fs::create_dir_all(&resources).expect("meeting resource directory");
    for name in ["swift-transformers_Hub.bundle", "swift-crypto_Crypto.bundle"] {
        let source = products.join(name);
        assert!(source.is_dir(), "required Swift resource bundle is missing: {name}");
        assert!(std::process::Command::new("/usr/bin/ditto").arg(source).arg(resources.join(name))
            .status().expect("copy Swift runtime resources").success(), "Swift resource copy failed");
    }
    // AEC3 was built for macOS 15. Keep it out of the main static archive so
    // macOS 14 can still launch; the Swift boundary loads this library only on 15+.
    let echo = resources.join("libOpenLessMeetingAEC.dylib");
    assert!(std::process::Command::new("xcrun")
        .args(["clang++", "-dynamiclib", "-target"]).arg(format!("{swift_arch}-apple-macosx15.0"))
        .args(["-Wl,-install_name,@rpath/libOpenLessMeetingAEC.dylib", "-Wl,-all_load"])
        .arg("-I").arg(root.join("vendor/webrtc-aec3/Sources/FluidAEC3Bridge/include"))
        .args(["-x", "c"]).arg(root.join("src/meetings/aec/MeetingAECExports.c")).args(["-x", "none"])
        .arg(root.join("vendor/webrtc-aec3/Artifacts/FluidAEC3.xcframework/macos-arm64_x86_64/libFluidAEC3-system-exact.a"))
        .args(["-framework", "Foundation", "-o"]).arg(&echo)
        .status().expect("build isolated AEC3 library").success(), "AEC3 library failed to link");
    if let Some(profile) = out.ancestors().nth(3) {
        std::fs::copy(&echo, profile.join("libOpenLessMeetingAEC.dylib")).expect("copy development AEC3 library");
        for name in ["swift-transformers_Hub.bundle", "swift-crypto_Crypto.bundle"] {
            assert!(std::process::Command::new("/usr/bin/ditto").arg(resources.join(name)).arg(profile.join(name))
                .status().expect("copy development Swift resources").success(), "development resource copy failed");
        }
    }
    let compiler = std::process::Command::new("xcrun").args(["--find", "swiftc"])
        .output().expect("find Swift compiler");
    assert!(compiler.status.success(), "Swift compiler path is unavailable");
    let compiler = std::path::PathBuf::from(String::from_utf8(compiler.stdout).unwrap().trim());
    let libraries = compiler.parent().unwrap().parent().unwrap().join("lib/swift/macosx");
    println!("cargo:rustc-link-search=native={}", libraries.display());
    println!("cargo:rustc-link-search=native={}", products.display());
    println!("cargo:rustc-link-lib=static=OpenLessMeetings");
    println!("cargo:rustc-link-lib=c++");
    for framework in ["Foundation", "AVFoundation", "CoreMedia", "ScreenCaptureKit", "AudioToolbox", "CoreAudio", "CoreML", "Accelerate", "Metal", "Security"] {
        println!("cargo:rustc-link-lib=framework={framework}");
    }
    println!("cargo:rustc-link-arg=-Wl,-rpath,/usr/lib/swift");
}

fn build_experimental_gemma() {
    const SOURCE: &str = "src/asr/local/experimental/gemma.swift";
    println!("cargo:rerun-if-changed={SOURCE}");
    let out = std::path::PathBuf::from(std::env::var_os("OUT_DIR").unwrap());
    let status = std::process::Command::new("xcrun")
        .args([
            "swiftc",
            "-O",
            "-parse-as-library",
            "-emit-library",
            "-static",
            "-module-name",
            "OpenlessGemma",
            "-target",
            "arm64-apple-macosx14.0",
            SOURCE,
            "-o",
        ])
        .arg(out.join("libOpenlessGemma.a"))
        .status()
        .expect("Swift compiler is required for the experimental Core ML adapter");
    assert!(
        status.success(),
        "experimental Core ML adapter failed to compile"
    );
    let swift = std::process::Command::new("xcrun")
        .args(["--find", "swiftc"])
        .output()
        .expect("find swiftc");
    let compiler = std::path::PathBuf::from(String::from_utf8(swift.stdout).unwrap().trim());
    let libraries = compiler
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .join("lib/swift/macosx");
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-search=native={}", libraries.display());
    println!("cargo:rustc-link-lib=static=OpenlessGemma");
    println!("cargo:rustc-link-lib=framework=CoreML");
    println!("cargo:rustc-link-lib=framework=Accelerate");
    println!("cargo:rustc-link-arg=-Wl,-rpath,/usr/lib/swift");
}

/// Native Apple adapters use availability checks. Rust links with
/// `-nodefaultlibs`, so the availability helper from Apple compiler-rt must be
/// added explicitly or Apple Silicon release links fail on macOS 14 targets.
fn link_macos_compiler_runtime() {
    let compiler = cc::Build::new().get_compiler();
    let output = std::process::Command::new(compiler.path())
        .arg("-print-resource-dir")
        .output()
        .expect("failed to query the macOS compiler resource directory");
    if !output.status.success() {
        panic!(
            "macOS compiler did not return its resource directory (status {})",
            output.status
        );
    }

    let resource_dir = String::from_utf8(output.stdout)
        .expect("macOS compiler resource directory was not UTF-8")
        .trim()
        .to_owned();
    let runtime_dir = std::path::PathBuf::from(resource_dir)
        .join("lib")
        .join("darwin");
    if !runtime_dir.join("libclang_rt.osx.a").exists() {
        panic!(
            "macOS compiler runtime not found at {}",
            runtime_dir.display()
        );
    }

    println!("cargo:rustc-link-search=native={}", runtime_dir.display());
    println!("cargo:rustc-link-lib=static=clang_rt.osx");
}

fn link_android_cpp_runtime() {
    // oboe-ext is partially statically linked into libc++; link c++abi as well
    // to provide __cxa_pure_virtual and other ABI symbols.
    println!("cargo:rustc-link-lib=c++_static");
    println!("cargo:rustc-link-lib=c++abi");
}

fn link_windows_common_controls_v6_manifest_dependency() {
    let mut source_path = std::path::PathBuf::from(
        std::env::var_os("OUT_DIR").expect("OUT_DIR must be set by Cargo"),
    );
    source_path.push("common-controls-v6-manifest-dependency.c");
    std::fs::write(
        &source_path,
        r#"#pragma comment(linker, "/manifestdependency:\"type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'\"")
int openless_common_controls_v6_manifest_dependency_anchor = 0;
"#,
    )
    .expect("write common controls manifest dependency source");
    cc::Build::new()
        .file(&source_path)
        .compile("openless_common_controls_v6_manifest_dependency");
    println!(
        "cargo:rustc-link-arg=/INCLUDE:openless_common_controls_v6_manifest_dependency_anchor"
    );
}
