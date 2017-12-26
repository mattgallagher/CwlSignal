// swift-tools-version:4.0
import PackageDescription

let package = Package(
   name: "CwlSignal",
   products: [.library(name: "CwlSignal", type: .dynamic, targets: ["CwlSignal"])],
	dependencies: [.package(url: "https://github.com/mattgallagher/CwlUtils.git", .revision("c6ae3a8d3ad48213094a9ebe3133830fd602a425"))],
	targets: [
		.target(
			name: "CwlSignal",
			dependencies: [
				.product(name: "CwlUtils")
			]
		)
	]
)
