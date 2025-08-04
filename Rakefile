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

    # Release
    sh "gem bump --version patch --tag --push --release"
  end
rescue LoadError
  # gem-release not available in this environment
end

task default: %i[test rubocop]
