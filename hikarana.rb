# frozen_string_literal: true

# hikarana — ひらがな／カタカナ練習問題(縦書き・マス目)ジェネレータ
#
# 動作要件: Ruby 4.0 以降(標準ライブラリのみ)、Typst 0.15 系
# 入力     : md/ 以下の "nnnn.md" / "nnnn_description.md"(1 ファイル = 1 ページ)
# 出力     : tmp/hikarana.typ を生成し、typst でコンパイルして out/hikarana.pdf を得る
#
# 使い方: ruby hikarana.rb [options]  (--help 参照)

require 'optparse'

require_relative 'lib/config'
require_relative 'lib/parser'
require_relative 'lib/layout'
require_relative 'lib/typst'
require_relative 'lib/images'

ROOT = File.expand_path(__dir__)

def main
  opts = { output: DEFAULT_OUTPUT, md_dir: DEFAULT_MD_DIR, img_dir: DEFAULT_IMG_DIR,
           tmp_dir: DEFAULT_TMP_DIR, only: nil, compile: true, font_paths: [],
           img_converter: :auto, img_dpi: IMG_DPI_DEFAULT, img_quality: IMG_QUALITY_DEFAULT }
  parser = OptionParser.new do |o|
    o.banner = "使い方: ruby #{File.basename($PROGRAM_NAME)} [options]\n" \
               "  #{DEFAULT_MD_DIR}/ の問題記述(markdown)から縦書きの練習問題 PDF を生成します。\n\n"
    o.on('-o', '--output PATH', String, "出力 PDF のパス(既定: #{DEFAULT_OUTPUT})") { |v| opts[:output] = v }
    o.on('--md-dir DIR', String, "問題記述のディレクトリ(既定: #{DEFAULT_MD_DIR})") { |v| opts[:md_dir] = v }
    o.on('--img-dir DIR', String, "画像のディレクトリ(既定: #{DEFAULT_IMG_DIR})") { |v| opts[:img_dir] = v }
    o.on('--tmp-dir DIR', String, "中間ファイル(.typ)のディレクトリ(既定: #{DEFAULT_TMP_DIR})") { |v| opts[:tmp_dir] = v }
    o.on('--only N,N', Array, '指定した問題種別番号(ファイル名の nnnn)のみ対象にする') { |v| opts[:only] = v }
    o.on('--img-dpi N', Integer, "埋め込み画像の解像度(30mm あたり。既定: #{IMG_DPI_DEFAULT})") { |v| opts[:img_dpi] = v }
    o.on('--img-quality Q', Integer, "埋め込み画像の JPEG 品質 1-100(既定: #{IMG_QUALITY_DEFAULT})") { |v| opts[:img_quality] = v }
    o.on('--img-converter C', IMG_CONVERTERS, "画像の変換器 #{IMG_CONVERTERS.join('/')}(既定: auto = vips → pillow の順に探す)") { |v| opts[:img_converter] = v }
    o.on('--no-img-convert', '画像を縮小・JPEG 化せず元ファイルをそのまま埋め込む(--img-converter none と同じ)') { opts[:img_converter] = :none }
    o.on('--no-compile', '.typ の生成のみ行い typst を実行しない') { opts[:compile] = false }
    o.on('--font-path DIR', String, 'typst に追加のフォントディレクトリを渡す(複数可)') { |v| opts[:font_paths] << v }
    o.on('-h', '--help', 'このヘルプを表示する') { puts o; exit }
  end
  parser.parse!(ARGV)

  md_dir  = File.expand_path(opts[:md_dir], ROOT)
  img_dir = File.expand_path(opts[:img_dir], ROOT)
  tmp_dir = File.expand_path(opts[:tmp_dir], ROOT)
  pdf_path = File.expand_path(opts[:output], ROOT)
  pdf_path += '.pdf' unless pdf_path.downcase.end_with?('.pdf')

  abort "error: 問題記述のディレクトリがありません: #{md_dir}" unless File.directory?(md_dir)
  abort "error: 画像のディレクトリがありません: #{img_dir}" unless File.directory?(img_dir)
  abort "error: --img-dpi は正の整数で指定してください: #{opts[:img_dpi]}" unless opts[:img_dpi].positive?
  abort "error: --img-quality は 1-100 で指定してください: #{opts[:img_quality]}" unless (1..100).cover?(opts[:img_quality])

  # 対象ファイルの収集(ファイル名の ASCII 順 = ページ順)
  all_md = Dir.children(md_dir).select { |f| f.downcase.end_with?('.md') }.sort
  files = all_md.select { |f| f.match?(MD_FILE_RE) }
  (all_md - files).each { |f| puts "note: ファイル名が nnnn.md / nnnn_description.md 形式でないため対象外: #{f}" }
  files.select! { |f| opts[:only].include?(f[MD_FILE_RE, 1]) } if opts[:only]
  abort 'error: 対象の問題記述ファイルがありません' if files.empty?

  pages = files.map do |f|
    path = File.join(md_dir, f)
    page = MdParser.new(path, img_dir: img_dir).parse
    check_page(page)
    puts format('%-40s -> %s  (%d 行, 解答 %d 語)', File.join(opts[:md_dir], f), page.number, page.lines.size, page.answers.size)
    page
  end

  Dir.mkdir(tmp_dir) unless File.directory?(tmp_dir)
  # 画像は元ファイルを残したまま、埋め込み用に縮小した JPEG を tmp/imgcache/ に作って使う。
  prepare_images(pages, img_dir: img_dir, cache_dir: File.join(tmp_dir, 'imgcache'),
                        dpi: opts[:img_dpi], quality: opts[:img_quality], converter: opts[:img_converter])
  typ_path = File.join(tmp_dir, "#{BASENAME}.typ")
  # Typst はルート外のファイルを読めないため、ルートを / にして画像を絶対パスで参照する。
  File.write(typ_path, build_typst(pages))
  puts "typ: #{typ_path}"

  warn "警告 #{$hk_warnings} 件" if $hk_warnings.positive?
  return unless opts[:compile]

  out_dir = File.dirname(pdf_path)
  Dir.mkdir(out_dir) unless File.directory?(out_dir)
  cmd = ['typst', 'compile', '--root', '/']
  opts[:font_paths].each { |d| cmd += ['--font-path', d] }
  cmd += [typ_path, pdf_path]
  abort 'error: typst のコンパイルに失敗しました' unless system(*cmd)

  n = begin
    `pdfinfo #{pdf_path.shellescape} 2>/dev/null`[/Pages:\s*(\d+)/, 1]
  rescue StandardError
    nil
  end
  puts "pdf: #{pdf_path}#{n ? " (#{n} ページ)" : ''}"
end

require 'shellwords'
main if __FILE__ == $PROGRAM_NAME
