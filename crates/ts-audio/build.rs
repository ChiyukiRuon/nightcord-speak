use std::{
    env, fs,
    io::Write,
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

fn run(command: &mut Command) {
    let result = command
        .output()
        .unwrap_or_else(|e| panic!("cannot execute {command:?}: {e}"));
    if !result.status.success() {
        let output = format!(
            "{}\n{}",
            String::from_utf8_lossy(&result.stdout),
            String::from_utf8_lossy(&result.stderr)
        );
        let log = PathBuf::from(env::var_os("OUT_DIR").unwrap()).join("apm-build.log");
        fs::write(&log, &output).expect("write APM build log");
        for line in output
            .lines()
            .filter(|l| l.contains("error") || l.contains("ERROR") || l.contains("FAILED"))
        {
            eprintln!("{line}");
        }
        panic!("APM build failed; full output: {}", log.display());
    }
}

fn archives(dir: &Path, found: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(dir).expect("read APM library directory") {
        let path = entry.expect("APM library entry").path();
        if path.is_dir() {
            archives(&path, found);
        } else if matches!(path.extension().and_then(|s| s.to_str()), Some("a" | "lib")) {
            found.push(path);
        }
    }
}

fn main() {
    let manifest = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap());
    // 避免 canonicalize 生成 Meson/Python 无法识别的 Windows 逐字路径前缀。
    let source = manifest
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .join("vendor/webrtc-apm");
    let out = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    let build = out.join("apm-build");
    let install = out.join("apm-install");
    let python = env::var_os("PYTHON").unwrap_or_else(|| "python".into());
    let compiler = cc::Build::new().cpp(true).cargo_debug(false).get_compiler();
    let mut setup = Command::new(&python);
    setup
        .args(["-m", "mesonbuild.mesonmain", "setup"])
        .arg(&build)
        .arg(&source)
        .arg("--prefix")
        .arg(&install)
        .args([
            "--default-library=static",
            "--buildtype=release",
            "--force-fallback-for=abseil-cpp",
            "-Db_vscrt=md",
            "-Dcpp_std=c++20",
            "-Dabseil-cpp:cpp_std=c++20",
        ]);
    if build.join("meson-private/coredata.dat").exists() {
        setup.arg("--reconfigure");
    }
    for (key, value) in compiler.env() {
        setup.env(key, value);
    }
    run(&mut setup);
    let mut compile = Command::new(&python);
    compile
        .args(["-m", "mesonbuild.mesonmain", "compile", "-C"])
        .arg(&build);
    for (key, value) in compiler.env() {
        compile.env(key, value);
    }
    run(&mut compile);
    run(Command::new(&python)
        .args(["-m", "mesonbuild.mesonmain", "install", "-C"])
        .arg(&build));

    let mut bridge = cc::Build::new();
    bridge
        .cpp(true)
        .std("c++20")
        .flag_if_supported("-Wno-unused-parameter")
        .file("native/apm.cpp")
        .include(source.join("webrtc"))
        .include(source.join("subprojects/abseil-cpp-20240722.0"));
    if env::var("CARGO_CFG_TARGET_OS").unwrap() == "windows" {
        bridge.define("WEBRTC_WIN", None).define("NOMINMAX", None);
    } else {
        bridge.define("WEBRTC_POSIX", None);
    }
    bridge.compile("nightcord_apm_bridge");

    let mut libs = Vec::new();
    archives(&install.join("lib"), &mut libs);
    libs.sort_by_key(|p| {
        (
            !p.file_stem()
                .unwrap()
                .to_string_lossy()
                .contains("webrtc-audio-processing"),
            p.clone(),
        )
    });
    // 合并归档，避免 GNU 链接器因 Abseil 静态库循环依赖或顺序而漏掉符号。
    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap();
    if target_os == "windows" {
        let mut archive = cc::Build::new().get_archiver();
        archive
            .arg(format!(
                "/OUT:{}",
                out.join("nightcord_apm_native.lib").display()
            ))
            .args(&libs);
        run(&mut archive);
    } else if target_os == "macos" {
        run(Command::new("libtool")
            .arg("-static")
            .arg("-o")
            .arg(out.join("libnightcord_apm_native.a"))
            .args(&libs));
    } else {
        let mut script = String::from("CREATE libnightcord_apm_native.a\n");
        for (index, path) in libs.iter().enumerate() {
            let name = format!("apm-archive-{index}.a");
            fs::copy(path, out.join(&name)).expect("copy APM archive");
            script.push_str(&format!("ADDLIB {name}\n"));
        }
        script.push_str("SAVE\nEND\n");
        let mut archive = cc::Build::new().get_archiver();
        let mut child = archive
            .arg("-M")
            .current_dir(&out)
            .stdin(Stdio::piped())
            .spawn()
            .expect("start archive merger");
        child
            .stdin
            .take()
            .unwrap()
            .write_all(script.as_bytes())
            .expect("write archive script");
        assert!(child.wait().expect("wait for archive merger").success());
    }
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=nightcord_apm_native");
    match target_os.as_str() {
        "windows" => println!("cargo:rustc-link-lib=winmm"),
        "macos" => println!("cargo:rustc-link-lib=framework=Foundation"),
        _ => {}
    }
    println!("cargo:rerun-if-changed=native/apm.cpp");
    println!(
        "cargo:rerun-if-changed={}",
        source.join("meson.build").display()
    );
    println!("cargo:rerun-if-changed={}", source.join("webrtc").display());
    println!("cargo:rerun-if-env-changed=PYTHON");
}
