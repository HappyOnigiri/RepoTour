#!/usr/bin/env ruby
# frozen_string_literal: true

require 'cgi'
require 'erb'
require 'fileutils'
require 'json'
require 'optparse'
require 'pathname'
require 'set'

class RepoTourRenderer
  MAIN_PAGES = [
    ['index', 'トップ', 'index.html'],
    ['product-overview', 'プロダクト概要', 'product-overview.html'],
    ['tech-stack', '技術スタック', 'tech-stack.html'],
    ['architecture', '設計', 'architecture.html'],
  ].freeze

  PAGE_LABELS = {
    'product-overview' => 'プロダクト概要',
    'tech-stack' => '技術スタック',
    'architecture' => 'コードベース設計',
  }.freeze

  def initialize(root:, output:, skill_dir:)
    @root = Pathname.new(root).expand_path
    @output = Pathname.new(output).absolute? ? Pathname.new(output) : @root.join(output)
    @skill_dir = Pathname.new(skill_dir).expand_path
    @templates_dir = @skill_dir.join('templates')
    @data_dir = @output.join('data')
    @features = []
    @features_by_id = {}
    @feature_details = {}
    @repo = {}
  end

  def render
    load_data
    prepare_output
    render_index
    render_main_page('product-overview', 'product-overview.html', read_json('product-overview.json'))
    render_main_page('tech-stack', 'tech-stack.html', read_json('tech-stack.json'))
    render_main_page('architecture', 'architecture.html', read_json('architecture.json'))
    render_features
  end

  private

  attr_reader :features, :feature, :page_data, :page_key, :page_label, :page_title, :current, :prefix, :content

  def load_data
    features_json = read_json('features.json')
    @features = Array(features_json['features'])
    @features_by_id = {}
    @features.each { |feature| @features_by_id[feature.fetch('id')] = feature }
    @repo = features_json['repo'] || {}
    Dir.glob(@data_dir.join('feature-details/*.json')).each do |path|
      detail = JSON.parse(File.read(path))
      @feature_details[detail.fetch('id')] = detail
      @repo = detail['repo'] if @repo.empty? && detail['repo'].is_a?(Hash)
    end
  end

  def prepare_output
    FileUtils.mkdir_p(@output.join('features'))
    FileUtils.cp(@skill_dir.join('assets/base-style.css'), @output.join('assets/style.css'))
    stale = @output.join('features.html')
    stale.delete if stale.exist?
    remove_stale_feature_pages
  end

  def read_json(relative_path)
    path = @data_dir.join(relative_path)
    return {} unless path.exist?

    JSON.parse(path.read)
  end

  def render_index
    @product_overview = read_json('product-overview.json')
    content = erb('index.html.erb').result(binding)
    write_html('index.html', layout(content:, page_title: 'トップ', current: 'index', prefix: ''))
  end

  def render_main_page(page_key, file_name, page_data)
    @page_key = page_key
    @page_label = PAGE_LABELS.fetch(page_key)
    @page_data = page_data
    content = erb('page.html.erb').result(binding)
    write_html(file_name, layout(content:, page_title: @page_label, current: page_key, prefix: ''))
  end

  def render_features
    @features.each do |feature_summary|
      @feature = @feature_details[feature_summary.fetch('id')] || feature_summary
      content = erb('feature.html.erb').result(binding)
      write_html("features/#{feature_file_name(@feature)}", layout(content:, page_title: @feature.fetch('name'), current: @feature.fetch('id'), prefix: '../'))
    end
  end

  def remove_stale_feature_pages
    expected = @features.map { |feature| feature_file_name(feature) }.to_set
    Dir.glob(@output.join('features/*.html')).each do |path|
      file_name = File.basename(path)
      FileUtils.rm_f(path) unless expected.include?(file_name)
    end
  end

  def layout(content:, page_title:, current:, prefix:)
    @content = content
    @page_title = document_title(page_title)
    @current = current
    @prefix = prefix
    erb('layout.html.erb').result(binding)
  end

  def write_html(relative_path, html)
    path = @output.join(relative_path)
    FileUtils.mkdir_p(path.dirname)
    path.write(html)
  end

  def erb(name)
    ERB.new(@templates_dir.join(name).read, trim_mode: '-')
  end

  def site_title
    title = @product_overview&.dig('title') || read_json('product-overview.json')['title']
    present?(title) ? title : "#{@root.basename} Repo Tour"
  end

  def document_title(display_page_name)
    page_name = present?(display_page_name) ? display_page_name : 'トップ'
    "#{site_title} | #{page_name}"
  end

  def product_overview
    @product_overview ||= read_json('product-overview.json')
  end

  def h(value)
    CGI.escapeHTML(value.to_s)
  end

  def present?(value)
    case value
    when nil then false
    when String then !value.strip.empty?
    when Array, Hash then !value.empty?
    else true
    end
  end

  def lead_for(data)
    data['lead'] || data['summary']&.first || 'このリポジトリのプロダクト概要、技術スタック、設計、機能を俯瞰するための静的レポートです。'
  end

  def feature_categories
    @features.map { |feature| feature['category'] || feature['product_area'] || 'その他' }.uniq
  end

  def data_file_count
    Dir.glob(@data_dir.join('**/*.json')).size
  end

  def features_by_category
    @features.group_by { |feature| feature['category'] || feature['product_area'] || 'その他' }
  end

  def feature_file_name(feature)
    page = feature['detail_page'].to_s
    return File.basename(page) if page.end_with?('.html')

    "#{feature.fetch('id')}.html"
  end

  def side_menu(prefix:, current:)
    sections = MAIN_PAGES.map do |id, label, href|
      current_attr = current == id ? ' aria-current="page"' : ''
      %(      <a class="side-link"#{current_attr} href="#{h(prefix + href)}">#{h(label)}</a>)
    end.join("\n")

    feature_groups = features_by_category.map do |category, category_features|
      links = category_features.map do |feature|
        href = prefix == '../' ? feature_file_name(feature) : "features/#{feature_file_name(feature)}"
        current_attr = current == feature['id'] ? ' aria-current="page"' : ''
        %(          <a class="side-link side-feature-link"#{current_attr} href="#{h(href)}">#{h(feature['name'])}</a>)
      end.join("\n")

      <<~HTML.rstrip
        <details class="side-feature-group" open>
          <summary>#{h(category)}</summary>
          <div class="side-feature-links">
        #{links}
          </div>
        </details>
      HTML
    end.join("\n")

    <<~HTML.rstrip
      <aside class="side-menu" aria-label="Repo Tour navigation">
        <div class="side-menu-inner">
          <section class="side-section">
            <p class="side-heading">主要ページ</p>
      #{sections}
          </section>
          <section class="side-section">
            <p class="side-heading">機能一覧</p>
      #{feature_groups}
          </section>
        </div>
      </aside>
    HTML
  end

  def paragraphs(values)
    Array(values).map { |value| "<p>#{h(value)}</p>" }.join("\n")
  end

  def list(values)
    items = Array(values).select { |value| present?(value) }
    return '<p class="muted">不明点として扱います。</p>' if items.empty?

    "<ul>#{items.map { |value| "<li>#{h(value)}</li>" }.join}</ul>"
  end

  def capability_content(feature)
    sections = Array(feature['capability_sections']).select { |section| present?(section['items']) }
    return list(feature['capabilities']) if sections.empty?

    sections.map do |section|
      title = section['title']
      body = list(section['items'])
      if present?(title)
        "<section class=\"subsection\"><h3>#{h(title)}</h3>#{body}</section>"
      else
        body
      end
    end.join("\n")
  end

  def ordered_list(values)
    items = Array(values).select { |value| present?(value) }
    return '<p class="muted">不明点として扱います。</p>' if items.empty?

    "<ol>#{items.map { |value| "<li>#{h(value)}</li>" }.join}</ol>"
  end

  def concept_list(concepts)
    items = Array(concepts).map do |concept|
      if concept.is_a?(Hash)
        "<li><strong>#{h(concept['name'])}</strong><span class=\"muted\"> #{h(concept['description'])}</span></li>"
      else
        "<li>#{h(concept)}</li>"
      end
    end
    "<ul>#{items.join}</ul>"
  end

  def render_page_sections(page_key, data)
    case page_key
    when 'product-overview'
      render_product_overview(data)
    when 'tech-stack'
      render_tech_stack(data)
    when 'architecture'
      render_architecture(data)
    else
      ''
    end
  end

  def render_product_overview(data)
    sections = []
    sections << panel('概要', paragraphs(data['summary'])) if present?(data['summary'])
    sections << panel('想定読者', list(data['audience'])) if present?(data['audience'])
    sections << panel('主要な概念', concept_list(data['major_concepts'])) if present?(data['major_concepts'])
    sections << panel('最初に読む場所', list(data['first_reads'])) if present?(data['first_reads'])
    sections << evidence(data['evidence_files'])
    sections.join("\n")
  end

  def render_tech_stack(data)
    Array(data['groups']).map do |group|
      cards = Array(group['items']).map do |item|
        <<~HTML
          <article class="card">
            <h3>#{h(item['name'])}</h3>
            <p>#{h(item['usage'])}</p>
            #{file_list(item['evidence_files'], prefix: '')}
          </article>
        HTML
      end.join("\n")
      panel(group['name'], %(<div class="grid">#{cards}</div>))
    end.join("\n")
  end

  def render_architecture(data)
    sections = []
    sections << panel('明示されている方針', list(data['explicit_policy'])) if present?(data['explicit_policy'])
    sections << panel('コードから観察できる傾向', list(data['observed_tendencies'])) if present?(data['observed_tendencies'])
    if present?(data['pattern_notes'])
      body = Array(data['pattern_notes']).map { |note| "<h3>#{h(note['label'])}</h3><p>#{h(note['description'])}</p>" }.join("\n")
      sections << panel('設計パターンとの近さ', body)
    end
    sections << panel('配置ルール', table(data['placement_table'], %w[change place note])) if present?(data['placement_table'])
    sections << panel('最初に読むファイル', file_list(data['first_files'], prefix: '')) if present?(data['first_files'])
    sections << evidence(data['evidence_files'])
    sections.join("\n")
  end

  def panel(title, body)
    return '' unless present?(body)

    <<~HTML
      <section class="panel">
        <h2>#{h(title)}</h2>
        #{body}
      </section>
    HTML
  end

  def evidence(files)
    return '' unless present?(files)

    <<~HTML
      <details class="evidence">
        <summary>根拠ファイル</summary>
        #{file_list(files, prefix: '')}
      </details>
    HTML
  end

  def table(rows, keys)
    header = keys.map { |key| "<th>#{h(key)}</th>" }.join
    body = Array(rows).map do |row|
      "<tr>#{keys.map { |key| "<td>#{h(row[key])}</td>" }.join}</tr>"
    end.join
    %(<div class="table-wrap"><table><thead><tr>#{header}</tr></thead><tbody>#{body}</tbody></table></div>)
  end

  def file_list(files, prefix:)
    items = Array(files).filter_map do |file|
      path = file.is_a?(Hash) ? file['path'] : file.to_s
      next unless present?(path)

      note = file.is_a?(Hash) ? file['note'] : nil
      links = file_links(path, prefix:)
      <<~HTML
        <li class="file-row">
          <span class="file-name" title="#{h(path)}">#{h(display_file_name(path))}</span>
          #{links}
          #{%(<span class="file-note">#{h(note)}</span>) if present?(note)}
          <details><summary>相対パス</summary><code>#{h(path)}</code></details>
        </li>
      HTML
    end
    return '<p class="muted">不明点として扱います。</p>' if items.empty?

    %(<ul class="file-list">#{items.join}</ul>)
  end

  def file_links(path, prefix:)
    links = []
    github = github_url(path)
    cursor = cursor_url(path)
    vscode = vscode_url(path)
    links << text_link(github, 'GitHub', external: true) if github
    links << text_link(cursor, 'Cursor') if cursor
    links << text_link(vscode, 'VS Code') if vscode
    links << copy_file_path_button(path)
    links.join("\n")
  end

  def text_link(url, label, external: false)
    target_attr = external ? ' target="_blank" rel="noopener noreferrer"' : ''
    %(<a class="file-link" href="#{h(url)}"#{target_attr}>#{h(label)}</a>)
  end

  def github_url(path)
    owner = @repo['github_owner']
    repo = @repo['github_repo']
    ref = @repo['commit'] || @repo['git_ref'] || @repo['branch']
    return nil unless present?(owner) && present?(repo) && present?(ref)

    "https://github.com/#{CGI.escape(owner)}/#{CGI.escape(repo)}/blob/#{CGI.escape(ref)}/#{path.split('/').map { |part| CGI.escape(part) }.join('/')}"
  end

  def cursor_url(path)
    root = @repo['repository_root'] || @root.to_s
    return nil unless present?(root)

    editor_file_url('cursor', File.join(root, path))
  end

  def vscode_url(path)
    root = @repo['repository_root'] || @root.to_s
    return nil unless present?(root)

    editor_file_url('vscode', File.join(root, path))
  end

  def editor_file_url(scheme, absolute_path)
    path = absolute_path.start_with?('/') ? absolute_path : "/#{absolute_path}"
    "#{scheme}://file#{path}"
  end

  def copy_file_path_button(path)
    %(<button class="file-copy" type="button" data-copy-path="#{h(path)}" title="相対パスをコピー" aria-label="相対パスをコピー"><svg viewBox="0 0 24 24" aria-hidden="true" focusable="false"><path d="M8 8.5a2 2 0 0 1 2-2h7a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2h-7a2 2 0 0 1-2-2v-9Z"></path><path d="M5 15.5V6.5a2 2 0 0 1 2-2h7"></path></svg><span class="sr-only">相対パスをコピー</span></button>)
  end

  def display_file_name(path)
    basename = File.basename(path)
    parent = File.basename(File.dirname(path))
    parent == '.' ? basename : "#{basename}（#{parent}）"
  end

  def related_features(feature)
    Array(feature['related_feature_ids']).filter_map { |id| @features_by_id[id] }
  end

  def render_unknowns(points)
    return '' unless present?(points)

    <<~HTML
      <section class="unknowns">
        <h2>不明点</h2>
        #{list(points)}
      </section>
    HTML
  end
end

options = {
  root: Dir.pwd,
  output: 'docs/repo-tour',
  skill_dir: File.expand_path('..', __dir__),
}

OptionParser.new do |parser|
  parser.banner = 'Usage: render_repo_tour.rb [--root PATH] [--output PATH] [--skill-dir PATH]'
  parser.on('--root PATH', 'Repository root') { |value| options[:root] = value }
  parser.on('--output PATH', 'Repo tour output directory') { |value| options[:output] = value }
  parser.on('--skill-dir PATH', 'Skill directory containing templates/assets') { |value| options[:skill_dir] = value }
end.parse!

RepoTourRenderer.new(**options).render
