# frozen_string_literal: true

require "bundler/gem_tasks"
require "minitest/test_task"

Minitest::TestTask.create

require "rubocop/rake_task"

RuboCop::RakeTask.new

begin
  require "gem/release"

  desc "Release with changelog"
  task :gem_release do
    # Generate changelog first
    sh "bundle exec github_changelog_generator  -u Hyper-Unearthing -p llm_gateway"
    sh "git add CHANGELOG.md"
    sh "git commit -m 'Update changelog' || echo 'No changelog changes'"

    # Ask for version bump type
    print "What type of version bump? (major/minor/patch): "
    version_type = $stdin.gets.chomp.downcase

    unless %w[major minor patch].include?(version_type)
      puts "Invalid version type. Please use major, minor, or patch."
      exit 1
    end

    # Release
    sh "gem bump --version #{version_type} --tag --push --release"
  end
rescue LoadError
  # gem-release not available in this environment
end

task default: %i[test rubocop]
