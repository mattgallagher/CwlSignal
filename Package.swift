// swift-tools-version:5.0
import PackageDescription

let package = Package(
   name: "CwlSignal",
	platforms: [
		.iOS(.v10),
		.macOS(.v10_12)
	],
   products: [
   	.library(name: "CwlSignal", type: .dynamic, targets: ["CwlSignal"])
	],
	dependencies: [
		.package(url: "https://github.com/mattgallagher/CwlUtils.git", from: Version(3, 0, 0, prereleaseIdentifiers: ["-beta.1"])),
		.package(url: "https://github.com/mattgallagher/CwlPreconditionTesting.git", from: Version(2, 0, 0, prereleaseIdentifiers: ["-beta.1"]))
	],
	targets: [
		.target(
			name: "CwlSignal",
			dependencies: [
				.product(name: "CwlUtils")
			]
		),
		.testTarget(
			name: "CwlSignalTests",
			dependencies: [
				.target(name: "CwlSignal"),
				.product(name: "CwlPreconditionTesting")
			]
		)
	]
)
