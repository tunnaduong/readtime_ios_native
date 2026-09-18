#!/usr/bin/env ruby
# Regenerates the small, dependency-free Xcode project around the SwiftUI source.

require "xcodeproj"

project = Xcodeproj::Project.new("ReadTimeNative.xcodeproj")
target = project.new_target(:application, "ReadTimeNative", :ios, "18.0")

target.build_configurations.each do |configuration|
  configuration.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.tunnaduong.readtime"
  configuration.build_settings["PRODUCT_NAME"] = "ReadTime"
  configuration.build_settings["INFOPLIST_FILE"] = "ReadTime/Info.plist"
  configuration.build_settings["GENERATE_INFOPLIST_FILE"] = "NO"
  configuration.build_settings["SWIFT_VERSION"] = "5.0"
  configuration.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = "18.0"
  configuration.build_settings["TARGETED_DEVICE_FAMILY"] = "1"
  configuration.build_settings["CODE_SIGN_ENTITLEMENTS"] = "ReadTime/ReadTime.entitlements"
  configuration.build_settings["CODE_SIGN_STYLE"] = "Automatic"
  configuration.build_settings["DEVELOPMENT_TEAM"] = "62H5L8QDTS"
  configuration.build_settings["SWIFT_EMIT_LOC_STRINGS"] = "YES"
  configuration.build_settings["LOCALIZATION_PREFERS_STRING_CATALOGS"] = "YES"
end

app_group = project.main_group.new_group("ReadTime", "ReadTime")
config_group = app_group.new_group("Config", "Config")
xcconfig = config_group.new_file("ReadTime.xcconfig")
config_group.new_file("Secrets.example.xcconfig")
target.build_configurations.each { |configuration| configuration.base_configuration_reference = xcconfig }
source_file = app_group.new_file("ReadTimeApp.swift")
app_group.new_file("Info.plist")
app_group.new_file("ReadTime.entitlements")
target.add_file_references([source_file])
%w[Localizable.xcstrings InfoPlist.xcstrings PrivacyInfo.xcprivacy Settings.bundle Assets.xcassets].each do |name|
  target.resources_build_phase.add_file_reference(app_group.new_file(name))
end
%w[vi es ja zh-Hans].each { |region| project.root_object.known_regions << region }

resources_group = app_group.new_group("Resources", "Resources")
Dir.glob("ReadTime/Resources/*").sort.each do |path|
  resource = resources_group.new_file(File.basename(path))
  target.resources_build_phase.add_file_reference(resource)
end

project.save
