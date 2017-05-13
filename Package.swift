import PackageDescription

let package = Package(
	name: "CwlSignal",
	dependencies: [
		.Package(url: "/Users/matt/Projects/CwlUtils", Version(1, 1, 2)),
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
