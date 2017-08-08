import PackageDescription

let package = Package(
	name: "CwlSignal",
	dependencies: [
		.Package(url: "https://github.com/mattgallagher/CwlUtils.git", Version(1, 1, 0, prereleaseIdentifiers: ["beta", "22"])),
	],
	exclude: []
)
