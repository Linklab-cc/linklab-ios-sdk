#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
#
Pod::Spec.new do |s|
  s.name             = 'LinkLabSDK'
  s.version          = '0.1.0'
  s.summary          = 'LinkLab deep linking service SDK for iOS'
  s.description      = <<-DESC
  LinkLab SDK for iOS provides deep linking services to handle universal links and custom URL schemes.
  This SDK allows native iOS applications to handle dynamic links provided by LinkLab.
                       DESC
  s.homepage         = 'https://linklab.cc'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'LinkLab' => 'info@linklab.cc' }
  s.source           = { :git => 'https://github.com/Linklab-cc/linklab-ios-sdk.git', :tag => s.version.to_s }
  
  s.ios.deployment_target = '14.3'
  s.swift_version = '5.0'
  
  s.source_files = 'LinkLabSDK/Classes/**/*'
  
  s.resource_bundles = {
    'LinkLabSDK' => ['LinkLabSDK/Assets/*.png']
  }
  
  s.frameworks = 'UIKit', 'WebKit'
  
  # If you have dependencies
  # s.dependency 'Alamofire', '~> 5.4'
  
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
