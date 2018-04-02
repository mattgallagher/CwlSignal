// swift-tools-version:4.0
import PackageDescription

let package = Package(
   name: "CwlSignal",
   products: [.library(name: "CwlSignal", type: .dynamic, targets: ["CwlSignal"])],
	dependencies: [.package(url: "https://github.com/mattgallagher/CwlUtils.git", .revision("a94841e69feb24b7d3b2495675abc260f86476c8"))],
	targets: [
		.target(
			name: "CwlSignal",
			dependencies: [
				.product(name: "CwlUtils")
			]
		)
	]
)
