require "xcodeproj"

project_path = File.expand_path("../Tickemo/Tickemo.xcodeproj", __dir__)
project = Xcodeproj::Project.open(project_path)

def find_or_create_group(parent, display_name, path)
  parent.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == display_name } ||
    parent.new_group(display_name, path)
end

def register(group, sources_phase, names)
  names.each do |name|
    next if group.children.any? { |c| c.respond_to?(:path) && c.path == name }
    file_ref = group.new_reference(name)
    sources_phase.add_file_reference(file_ref)
    puts "Registered #{group.display_name}/#{name}"
  end
end

app_target = project.targets.find { |t| t.name == "Tickemo" }
raise "Tickemo target not found" unless app_target

tickemo_group = project.main_group.children.find do |c|
  c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == "Tickemo"
end
raise "Tickemo group not found" unless tickemo_group

app_sources_phase = app_target.build_phases.find { |bp| bp.is_a?(Xcodeproj::Project::Object::PBXSourcesBuildPhase) }

components_group = find_or_create_group(tickemo_group, "Components", "Tickemo/Components")
register(components_group, app_sources_phase, %w[VenueMapCardView.swift VenueSearchField.swift])

support_group = find_or_create_group(tickemo_group, "Support", "Tickemo/Support")
register(support_group, app_sources_phase, %w[ChekiRecordVenue.swift])

project.save
puts "Saved #{project_path}"
