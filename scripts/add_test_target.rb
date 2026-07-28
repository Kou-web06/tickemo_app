require "xcodeproj"

project_path = File.expand_path("../Tickemo/Tickemo.xcodeproj", __dir__)
project = Xcodeproj::Project.open(project_path)
app_target = project.targets.find { |t| t.name == "Tickemo" }
raise "Tickemo target not found" unless app_target

test_target = project.targets.find { |t| t.name == "TickemoTests" }

if test_target
  puts "TickemoTests target already exists (#{test_target.uuid})"
else
  test_target = project.new_target(:unit_test_bundle, "TickemoTests", :ios, "17.6", nil, :swift)
  test_target.add_dependency(app_target)

  test_target.build_configurations.each do |config|
    # PRODUCT_NAME isn't inherited from the project-level "$(TARGET_NAME)"
    # default for a target created this way (verified empirically: it built
    # an empty-named ".xctest" bundle without this), so set it explicitly.
    config.build_settings["PRODUCT_NAME"] = "$(TARGET_NAME)"
    config.build_settings["GENERATE_INFOPLIST_FILE"] = "YES"
    config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.anonymous.Tickemo.TickemoTests"
    config.build_settings["TEST_HOST"] = "$(BUILT_PRODUCTS_DIR)/Tickemo.app/Tickemo"
    config.build_settings["BUNDLE_LOADER"] = "$(TEST_HOST)"
    config.build_settings["SWIFT_VERSION"] = "5.0"
  end

  puts "Created TickemoTests target (#{test_target.uuid})"
end

tests_group = project.main_group.children.find do |c|
  c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == "TickemoTests"
end
tests_group ||= project.main_group.new_group("TickemoTests", "TickemoTests")

sources_phase = test_target.build_phases.find { |bp| bp.is_a?(Xcodeproj::Project::Object::PBXSourcesBuildPhase) }

test_file_name = "LegacyStoreModelsTests.swift"
unless tests_group.children.any? { |c| c.respond_to?(:path) && c.path == test_file_name }
  file_ref = tests_group.new_reference(test_file_name)
  sources_phase.add_file_reference(file_ref)
  puts "Registered TickemoTests/#{test_file_name}"
end

project.save
puts "Saved #{project_path}"
puts "test_target_uuid=#{test_target.uuid}"
