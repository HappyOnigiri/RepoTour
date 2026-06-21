#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'optparse'
require 'pathname'
require 'cgi'

options = {
  root: Dir.pwd,
  output: 'docs/repo-tour',
}

OptionParser.new do |parser|
  parser.banner = 'Usage: validate_repo_tour.rb [--root PATH] [--output PATH]'
  parser.on('--root PATH', 'Repository root') { |value| options[:root] = value }
  parser.on('--output PATH', 'Repo tour output directory') { |value| options[:output] = value }
end.parse!

root = Pathname.new(options[:root]).expand_path
output = Pathname.new(options[:output]).absolute? ? Pathname.new(options[:output]) : root.join(options[:output])
errors = []
warnings = []

features_path = output.join('data/features.json')
if features_path.exist?
  features = JSON.parse(features_path.read).fetch('features')
else
  features = []
  errors << 'missing data/features.json'
end

product_overview_path = output.join('data/product-overview.json')
site_title = if product_overview_path.exist?
               JSON.parse(product_overview_path.read)['title']
             end

html_files = Dir.glob(output.join('**/*.html')).map { |path| Pathname.new(path) }
feature_pages = Dir.glob(output.join('features/*.html')).map { |path| Pathname.new(path) }
feature_detail_paths = Dir.glob(output.join('data/feature-details/*.json')).map { |path| Pathname.new(path) }

errors << 'features.html must not exist' if output.join('features.html').exist?
errors << "feature page count mismatch: expected #{features.size}, got #{feature_pages.size}" unless feature_pages.size == features.size
errors << 'no html files generated' if html_files.empty?

html_files.each do |path|
  html = path.read
  rel = path.relative_path_from(root)
  errors << "#{rel}: missing side-menu" unless html.include?('class="side-menu"')
  errors << "#{rel}: missing side menu scroll restoration" unless html.include?('repoTour.sideMenuScrollTop') && html.include?('sessionStorage')
  errors << "#{rel}: contains legacy site-nav" if html.include?('class="site-nav"')
  errors << "#{rel}: contains legacy feature card/list classes" if html.match?(/feature-card|feature-section/)
  errors << "#{rel}: links to removed features.html" if html.match?(/href="[^"]*features\.html/)
  if site_title.to_s.strip != ''
    escaped_site_title = CGI.escapeHTML(site_title.to_s)
    errors << "#{rel}: page title must be \"#{site_title} | {表示ページ名}\"" unless html.include?("<title>#{escaped_site_title} | ")
  end

  side_link_count = html.scan('class="side-link side-feature-link"').size
  errors << "#{rel}: side feature links mismatch: expected #{features.size}, got #{side_link_count}" unless side_link_count == features.size

  if html.include?('class="file-row"')
    errors << "#{rel}: file rows missing VSCode links" unless html.include?('vscode://file/')
    errors << "#{rel}: file rows missing copy buttons" unless html.include?('class="file-copy"') && html.include?('data-copy-path=')
    errors << "#{rel}: file path copy button must use an icon, not visible Copy text" if html.match?(/<button[^>]*class="file-copy"[^>]*>\s*Copy\s*<\/button>/)
    errors << "#{rel}: missing file path copy handler" unless html.include?('navigator.clipboard') && html.include?('repoTour.copyFilePath')
  end

  html.scan(/href="([^"]+)"/).flatten.each do |href|
    next if href.match?(/\A(?:https?:|cursor:|vscode:|mailto:|#)/)

    local = href.split('#', 2).first
    next if local.to_s.empty?

    destination = Pathname.new(File.expand_path(local, path.dirname))
    errors << "#{rel}: broken local href #{href}" unless destination.exist?
  end
end

css_path = output.join('assets/style.css')
if css_path.exist?
  css = css_path.read
  errors << 'assets/style.css: missing stable page scrollbar' unless css.include?('overflow-y: scroll') && css.include?('scrollbar-gutter: stable')
  errors << 'assets/style.css: contains multi-column content grid' if css.match?(/grid-template-columns:\s*repeat\(/) || css.match?(/grid-template-columns:\s*1\.1fr/)
else
  errors << 'missing assets/style.css'
end

if feature_detail_paths.any?
  capability_counts = feature_detail_paths.map do |path|
    detail = JSON.parse(path.read)
    sections = Array(detail['capability_sections'])
    section_count = sections.sum { |section| Array(section['items']).size }
    [Array(detail['capabilities']).size, section_count].max
  end
  fixed_three_count = capability_counts.count(3)
  fixed_three_ratio = fixed_three_count.to_f / capability_counts.size
  if capability_counts.size >= 20 && fixed_three_ratio >= 0.8
    errors << "feature capabilities appear fixed at 3 items: #{fixed_three_count}/#{capability_counts.size}"
  end

  missing_naming_evidence = []
  codeish_wording = []
  codeish_patterns = [
    /\b[A-Z][A-Za-z0-9_]+::[A-Za-z0-9_:]+\b/,
    /\b[A-Z][A-Za-z0-9_]+(?:Controller|Service|Job|Task|History|Request|Response)\b/,
    /\b[a-z]+_[a-z0-9_]+\b/,
  ]

  feature_detail_paths.each do |path|
    detail = JSON.parse(path.read)
    name = detail['name'] || path.basename('.json').to_s
    naming_evidence = Array(detail['naming_evidence']).reject { |entry| entry.to_s.strip.empty? }
    uncertain_text = Array(detail['uncertain_points']).join(' ')
    if naming_evidence.empty? && !uncertain_text.match?(/表示名|正式名|正式名称|名称|文言|未確認/)
      missing_naming_evidence << "#{path.basename}: #{name}"
    end

    %w[summary capabilities scenarios].each do |field|
      values = Array(detail[field])
      values = [detail[field]] if detail[field].is_a?(String)
      values.compact.each do |value|
        text = value.to_s
        next unless codeish_patterns.any? { |pattern| text.match?(pattern) }

        codeish_wording << "#{path.basename}: #{name} #{field}: #{text[0,120]}"
      end
    end
  end

  if missing_naming_evidence.any?
    warnings << "features missing naming_evidence or wording uncertainty: #{missing_naming_evidence.size}/#{feature_detail_paths.size}"
    warnings.concat(missing_naming_evidence.first(20).map { |item| "  - #{item}" })
  end

  if codeish_wording.any?
    warnings << "feature wording may still expose code identifiers: #{codeish_wording.size} entries"
    warnings.concat(codeish_wording.first(20).map { |item| "  - #{item}" })
  end
end

if errors.empty?
  puts "repo tour validation ok: #{features.size} features, #{html_files.size} html files"
  warn warnings.join("\n") if warnings.any?
else
  warn errors.join("\n")
  exit 1
end
