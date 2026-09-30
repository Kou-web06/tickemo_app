require "xcodeproj"

project_path = File.expand_path("../Tickemo.xcodeproj", __dir__)
project = Xcodeproj::Project.open(project_path)

def find_group(parent, display_name)
  parent.recursive_children_groups.find { |g| g.display_name == display_name } ||
    raise("#{display_name} group not found")
end

def register(group, sources_phase, names)
  names.each do |name|
    next if group.children.any? { |c| c.respond_to?(:path) && c.path == name }
    file_ref = group.new_reference(name)
    sources_phase.add_file_reference(file_ref)
    puts "Registered #{group.display_name}/#{name}"
  end
end

# --- Tickemo app target ---
app_target = project.targets.find { |t| t.name == "Tickemo" }
raise "Tickemo target not found" unless app_target
app_sources_phase = app_target.build_phases.find { |bp| bp.is_a?(Xcodeproj::Project::Object::PBXSourcesBuildPhase) }

register(find_group(project.main_group, "Support"), app_sources_phase, %w[TicketSchedule.swift])

# --- TickemoTests target ---
test_target = project.targets.find { |t| t.name == "TickemoTests" }
raise "TickemoTests target not found" unless test_target
test_sources_phase = test_target.build_phases.find { |bp| bp.is_a?(Xcodeproj::Project::Object::PBXSourcesBuildPhase) }

register(find_group(project.main_group, "TickemoTests"), test_sources_phase, %w[TicketScheduleTests.swift])

project.save
puts "Saved #{project_path}"
