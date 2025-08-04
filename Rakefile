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
    # Safety checks: ensure we're on main and up-to-date
    current_branch = `git branch --show-current`.strip
    unless current_branch == "main"
      puts "Error: You must be on the main branch to release. Current branch: #{current_branch}"
      exit 1
    end

    # Check if branch is up-to-date with remote
    sh "git fetch origin"
    local_commit = `git rev-parse HEAD`.strip
    remote_commit = `git rev-parse origin/main`.strip
    unless local_commit == remote_commit
      puts "Error: Your main branch is not in sync with origin/main. Please pull the latest changes."
      exit 1
    end

    # Check for uncommitted changes
    unless `git status --porcelain`.strip.empty?
      puts "Error: You have uncommitted changes. Please commit or stash them before releasing."
      exit 1
    end

    # Ask for version bump type first
    print "What type of version bump? (major/minor/patch): "
    version_type = $stdin.gets.chomp.downcase

    unless %w[major minor patch].include?(version_type)
      puts "Invalid version type. Please use major, minor, or patch."
      exit 1
    end

    # Bump version without committing yet to get new version
    sh "gem bump --version #{version_type} --no-commit"

    # Get the new version
    new_version = `ruby -e "puts Gem::Specification.load('llm_gateway.gemspec').version"`.strip

    # Generate changelog with proper version
    sh "bundle exec github_changelog_generator " \
       "-u Hyper-Unearthing -p llm_gateway --future-release v#{new_version}"

    # Bundle to update Gemfile.lock
    sh "bundle"

    # Add all changes and commit in one go
    sh "git add ."
    sh "git commit -m 'Bump llm_gateway to $(ruby -e \"puts Gem::Specification.load('llm_gateway.gemspec').version\")'"

    # Tag and push
    sh "git tag v$(ruby -e \"puts Gem::Specification.load('llm_gateway.gemspec').version\")"
    sh "git push origin main --tags"

    # Release the gem
    sh "gem push $(gem build llm_gateway.gemspec | grep 'File:' | awk '{print $2}')"
  end
rescue LoadError
  # gem-release not available in this environment
end

task default: %i[test rubocop]
