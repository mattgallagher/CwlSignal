// swift-tools-version:4.0
import PackageDescription

let package = Package(
   name: "CwlSignal",
   products: [
   	.library(name: "CwlSignal", type: .dynamic, targets: ["CwlSignal"])
	],
	dependencies: [
		.package(url: "https://github.com/mattgallagher/CwlUtils.git", from: "2.0.0"),
		.package(url: "https://github.com/mattgallagher/CwlPreconditionTesting.git", from: "1.1.0"),
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
