import PackageDescription

let package = Package(
	name: "CwlSignal",
	dependencies: [
		.Package(url: "/Users/matt/Projects/CwlUtils", majorVersion: 1),
	],
	exclude: [
		"LICENSE.txt",
		"ReadMe.md",
		"CwlSignal.playground",
		"Sources/CwlPackageFetch",
		"Sources/CwlSignal/CwlSignal.h",
		"Sources/CwlSignal/Info.plist",
		"Tests/CwlSignalTests/Info.plist"
	]
)
