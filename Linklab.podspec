Pod::Spec.new do |s|
  s.name             = 'Linklab'
  s.version          = '0.3.0'
  s.summary          = 'Linklab deep linking SDK for iOS'
  s.description      = 'Linklab SDK for iOS resolves Linklab universal links and deferred deep links (pasteboard / IP attribution).'
  s.homepage         = 'https://linklab.cc'
  s.license          = { :type => 'Apache Version 2.0', :file => 'LICENSE' }
  s.author           = { 'Linklab' => 'info@linklab.cc' }

  s.source           = { :git => 'https://github.com/Linklab-cc/linklab-ios-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '14.3'
  s.swift_version = '5.9'

  s.source_files = 'Sources/Linklab/**/*.swift'
  s.resource_bundles = { 'Linklab' => ['Sources/Linklab/PrivacyInfo.xcprivacy'] }

  s.frameworks = 'UIKit'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }

  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files = 'Tests/LinklabTests/**/*.swift'
    test_spec.framework = 'XCTest'
  end
end
