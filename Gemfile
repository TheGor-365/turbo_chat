source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.4.12"

gem "rails", "~> 8.1.0", ">= 8.1.4.1"
gem "sprockets-rails"
gem "pg", "~> 1.1"
gem "puma", "~> 8.0", ">= 8.0.2"
gem "jsbundling-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "cssbundling-rails"
gem "jbuilder"
gem "redis", "~> 4.0"
gem "tzinfo-data", platforms: %i[ mingw mswin x64_mingw jruby ]
gem "bootsnap", require: false
gem "devise", "~> 5.0", ">= 5.0.4"
gem "image_processing", "~> 1.2"
gem "mini_magick"
gem "pagy", "~> 6.0"
# Keep Minitest 5 during the incremental Rails upgrade; re-evaluate on Rails 8.
gem "minitest", "~> 5.25"

# gem "kredis"
# gem "bcrypt", "~> 3.1.7"
# gem "sassc-rails"

group :development, :test do
  gem "debug", platforms: %i[ mri mingw x64_mingw ]
end

group :development do
  gem "web-console"

  # gem "rack-mini-profiler"
  # gem "spring"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
  # Selenium 4.11+ includes official Selenium Manager; obsolete webdrivers blocks security updates.
end
