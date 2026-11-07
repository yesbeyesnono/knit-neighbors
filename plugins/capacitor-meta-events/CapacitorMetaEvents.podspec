Pod::Spec.new do |s|
  s.name = 'CapacitorMetaEvents'
  s.version = '1.0.0'
  s.summary = 'knitup Meta app events'
  s.license = 'UNLICENSED'
  s.homepage = 'https://knitup.co.kr'
  s.author = 'FIRMTECH'
  s.source = { :git => 'https://github.com/yesbeyesnono/knit-neighbors.git', :tag => s.version.to_s }
  s.source_files = 'ios/Sources/**/*.{swift,h,m}'
  s.ios.deployment_target = '15.0'
  s.dependency 'Capacitor'
  s.dependency 'FBSDKCoreKit', '19.0.0'
  s.swift_version = '5.1'
end
