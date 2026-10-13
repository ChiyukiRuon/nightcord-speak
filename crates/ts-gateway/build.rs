fn main() {
    let pubspec =
        std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../apps/client/pubspec.yaml");
    println!("cargo:rerun-if-changed={}", pubspec.display());
    let contents = std::fs::read_to_string(pubspec).expect("read client product version");
    let version = contents
        .lines()
        .find_map(|line| line.strip_prefix("version:"))
        .map(str::trim)
        .filter(|version| !version.is_empty())
        .expect("client pubspec must declare a product version");
    println!("cargo:rustc-env=NIGHTCORD_PRODUCT_VERSION={version}");
}
