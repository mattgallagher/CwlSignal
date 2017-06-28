import PackageDescription

let package = Package(
	name: "CwlSignal",
	dependencies: [
		.Package(url: "https://github.com/mattgallagher/CwlUtils.git", Version(1, 1, 0, prereleaseIdentifiers: ["beta", "10"])),
	],
	exclude: [
		"LICENSE.txt",
		"ReadMe.md",
		"CwlSignal.playground",
		"Sources/CwlSignal/CwlSignal.h",
		"Sources/CwlSignal/Info.plist",
		"Tests/CwlSignalTests/Info.plist"
	]
)
