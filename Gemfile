# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in llm_gateway.gemspec
gemspec

group :development do
  gem "gem-release", "~> 2.2"
  gem "github_changelog_generator", "~> 1.16"
  gem "irb"
  gem "rake", "~> 13.0"
  gem "rubocop", "~> 1.21"
  gem "rubocop-rails-omakase", "~> 1.0"
end

group :test do
  gem "minitest", "~> 5.16"
  gem "mocha", "~> 2.0"
  gem "simplecov", "~> 0.22"
  gem "vcr", "~> 6.0"
  gem "webmock", "~> 3.0"
end

group :development, :test do
  gem "debug", ">= 1.0.0"
  gem "dotenv", "~> 2.8"
end
