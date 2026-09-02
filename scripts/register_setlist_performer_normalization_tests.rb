require "xcodeproj"

project_path = File.expand_path("../Tickemo/Tickemo.xcodeproj", __dir__)
project = Xcodeproj::Project.open(project_path)

def register(group, sources_phase, names)
  names.each do |name|
    next if group.children.any? { |c| c.respond_to?(:path) && c.path == name }
    file_ref = group.new_reference(name)
    sources_phase.add_file_reference(file_ref)
    puts "Registered #{group.display_name}/#{name}"
  end
end

test_target = project.targets.find { |t| t.name == "TickemoTests" }
raise "TickemoTests target not found" unless test_target

tests_group = project.main_group.children.find do |c|
  c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == "TickemoTests"
end
raise "TickemoTests group not found" unless tests_group

test_sources_phase = test_target.build_phases.find { |bp| bp.is_a?(Xcodeproj::Project::Object::PBXSourcesBuildPhase) }

register(tests_group, test_sources_phase, %w[SetlistDraftPerformerNormalizationTests.swift])

project.save
puts "Saved #{project_path}"
