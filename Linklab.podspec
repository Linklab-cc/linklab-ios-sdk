Pod::Spec.new do |s|
  s.name             = 'Linklab'
  s.version          = '0.2.2'
  s.summary          = 'LinkLab deep linking service SDK for iOS'
  s.description      = 'LinkLab SDK for iOS provides deep linking services to handle universal links and custom URL schemes.'
  s.homepage         = 'https://linklab.cc'
  s.license = { :type => 'Apache Version 2.0', :file => 'LICENSE' }
  s.author           = { 'LinkLab' => 'info@linklab.cc' }
  
  s.source           = { :git => 'https://github.com/Linklab-cc/linklab-ios-sdk.git', :tag => s.version.to_s }
  
  s.ios.deployment_target = '14.3'
  s.swift_version = '5.0'
  
  s.source_files = 'Sources/Linklab/**/*.swift'
  
  s.frameworks = 'UIKit', 'WebKit'
  
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  
  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'Tests/LinkLabTests/**/*.swift'
    test_spec.framework = 'XCTest'
  end
end
