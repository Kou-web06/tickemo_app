require "xcodeproj"

project_path = File.expand_path("../Tickemo/Tickemo.xcodeproj", __dir__)
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == "Tickemo" }
raise "Tickemo target not found" unless target

tickemo_group = project.main_group.children.find do |c|
  c.is_a?(Xcodeproj::Project::Object::PBXGroup) && c.display_name == "Tickemo"
end
raise "Tickemo group not found" unless tickemo_group

sources_phase = target.build_phases.find { |bp| bp.is_a?(Xcodeproj::Project::Object::PBXSourcesBuildPhase) }
frameworks_phase = target.build_phases.find { |bp| bp.is_a?(Xcodeproj::Project::Object::PBXFrameworksBuildPhase) }

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

# --- SPM package: RevenueCat, pinned to the exact version already shipping
# in the RN app (ios/Podfile.lock: RevenueCat 5.59.0), for continuity with
# real paying users rather than an unpinned upToNextMajor floor.
repo_url = "https://github.com/RevenueCat/purchases-ios"

existing_ref = project.root_object.package_references&.find do |ref|
  ref.respond_to?(:repositoryURL) && ref.repositoryURL == repo_url
end

package_ref = existing_ref
unless package_ref
  package_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  package_ref.repositoryURL = repo_url
  package_ref.requirement = { "kind" => "exactVersion", "version" => "5.59.0" }
  project.root_object.package_references ||= []
  project.root_object.package_references << package_ref
  puts "Added XCRemoteSwiftPackageReference for #{repo_url}"
end

existing_product = target.package_product_dependencies&.find { |dep| dep.product_name == "RevenueCat" }
unless existing_product
  product_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product_dep.package = package_ref
  product_dep.product_name = "RevenueCat"
  target.package_product_dependencies ||= []
  target.package_product_dependencies << product_dep

  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = product_dep
  frameworks_phase.files << build_file
  puts "Added RevenueCat package product dependency + build file"
end

# --- New Swift files
services_group = find_or_create_group(tickemo_group, "Services", "Tickemo/Services")
register(services_group, sources_phase, %w[PurchasesService.swift EarlyOfferService.swift])

screens_group = find_or_create_group(tickemo_group, "Screens", "Tickemo/Screens")
register(screens_group, sources_phase, %w[PaywallView.swift])

project.save
puts "Saved #{project_path}"
