Pod::Spec.new do |s|
  s.name          = "CwlUtils"
  s.version       = "2.0.0"
  
  s.summary       = "A collection of Swift utilities as documented on cocoawithlove.com"
  s.description   = <<-DESC
    Stack traces, system information with sysctl, presentation of unanticipated errors, random number generators, mutexes, dispatch timers, a Result type, copy-on-write double-ended queue, function execution contexts, testing actions over time. See [Cocoa with Love](https://cocoawithlove.com) for more.
  DESC
  
  s.homepage      = "https://github.com/mattgallagher/CwlUtils"
  s.license       = { :type => "ISC", :file => "LICENSE.txt" }
  s.author        = "Matt Gallagher"
  
  s.ios.deployment_target = "8.0"
  s.osx.deployment_target = "10.10"
  
  s.source        = { :git => "https://github.com/mattgallagher/CwlUtils.git", :branch => "xcode10" }
  s.source_files  = "Sources/CwlUtils/*.{swift,h}", "Sources/CwlFrameAddress/**/*.{c,h}"
end
