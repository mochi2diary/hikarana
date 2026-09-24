# frozen_string_literal: true

# 画像の埋め込み準備。元画像(img/)はそのまま残し、PDF に埋め込む用の縮小 JPEG を
# キャッシュディレクトリ(tmp/imgcache/)に作る。
#
# 変換器は次の順で自動選択する(--img-converter で固定もできる)。
#   1. vips   : ruby-vips gem + libvips(ネイティブ)。Ruby だけで完結する。
#   2. pillow : lib/imgconv.py(Python 3 + Pillow)を呼び出す。
#   3. none   : 変換せず元画像をそのまま埋め込む(警告を出す)。

require 'json'
require 'fileutils'

IMG_DPI_DEFAULT     = 600 # 30mm の画像エリアに対する解像度
IMG_QUALITY_DEFAULT = 90  # JPEG 品質(1-100)
IMG_CONVERTERS = %i[auto vips pillow none].freeze
IMGCONV_SCRIPT = File.join(__dir__, 'imgconv.py')

# 画像エリア(30mm)を dpi で埋めるときの長辺のピクセル数
def image_px(dpi)
  (IMAGE_SIZE / 72.0 * dpi).round
end

# 使える変換器を選ぶ。戻り値は :vips / :pillow / :none。
def select_converter(pref)
  return pref if %i[none pillow].include?(pref)

  if vips_available?
    :vips
  elsif pref == :vips
    hk_warn('ruby-vips(gem)または libvips が使えません(Pillow / 元画像にフォールバックします)。' \
            '導入: sudo apt install libvips42t64 && gem install ruby-vips')
    :pillow
  else
    :pillow
  end
end

def vips_available?
  require 'vips'
  true
rescue LoadError
  false
end

# 全ページの画像要素について埋め込みパス(el.embed)を決める。
# 変換できなかった画像は元画像にフォールバックする。
def prepare_images(pages, img_dir:, cache_dir:, dpi:, quality:, converter: :auto)
  images = pages.flat_map { |pg| pg.lines.flat_map { |l| l.elements.select { |e| e.type == :image && e.exists } } }
  images.each { |e| e.embed = File.join(img_dir, e.path) }
  return if images.empty?

  conv = select_converter(converter)
  return if conv == :none

  px = image_px(dpi)
  jobs = {} # src => dst (同じ画像が複数箇所にあっても 1 回だけ変換する)
  targets = {}
  images.each do |e|
    src = File.join(img_dir, e.path)
    dst = File.join(cache_dir, "#{e.path}.#{px}q#{quality}.jpg")
    (targets[dst] ||= []) << e
    jobs[src] = dst if !File.file?(dst) || File.mtime(dst) < File.mtime(src)
  end

  failed = []
  unless jobs.empty?
    jobs.each_value { |dst| FileUtils.mkdir_p(File.dirname(dst)) }
    results = conv == :vips ? run_vips(jobs, px, quality) : run_imgconv(jobs, px, quality)
    if results.nil?
      failed = jobs.values # 変換器が動かなかったので全て元画像を使う
    else
      results.each do |r|
        next if r['ok']

        hk_warn("画像の変換に失敗しました(元画像を埋め込みます): #{r['src']}: #{r['error']}")
        failed << r['dst']
      end
    end
  end

  targets.each do |dst, els|
    next if failed.include?(dst) || !File.file?(dst)

    els.each { |e| e.embed = dst }
  end
  puts "画像: #{targets.size} 件(変換 #{jobs.size - failed.size} 件, キャッシュ #{targets.size - jobs.size} 件, #{conv}) " \
       "長辺 #{px}px(#{dpi}dpi) JPEG 品質 #{quality} → #{cache_dir}"
end

# ---- vips (ruby-vips) ------------------------------------------------------

# 長辺 px に縮小(拡大はしない)し、透過は白に合成、sRGB・4:4:4 の JPEG で保存する。
def run_vips(jobs, px, quality)
  jobs.map do |src, dst|
    begin
      # thumbnail は EXIF の回転を反映し、size: :down で拡大を抑止する。
      im = Vips::Image.thumbnail(src, px, height: px, size: :down)
      im = im.flatten(background: [255, 255, 255]) if im.has_alpha?
      im = im.colourspace(:srgb) unless im.interpretation == :srgb
      im.jpegsave(dst, Q: quality, optimize_coding: true, subsample_mode: :off)
      { 'src' => src, 'dst' => dst, 'ok' => true }
    rescue Vips::Error, StandardError => e
      { 'src' => src, 'dst' => dst, 'ok' => false, 'error' => e.message.strip }
    end
  end
end

# ---- pillow (imgconv.py) ---------------------------------------------------

# imgconv.py を 1 回呼び出して一括変換する。実行できなければ警告して nil を返す。
def run_imgconv(jobs, px, quality)
  out = IO.popen(['python3', IMGCONV_SCRIPT, px.to_s, quality.to_s], 'r+') do |io|
    io.write(JSON.generate(jobs.to_a))
    io.close_write
    io.read
  end
  status = $CHILD_STATUS || $?
  data = begin
    JSON.parse(out)
  rescue JSON::ParserError
    nil
  end
  if data.is_a?(Hash) && data['fatal']
    hk_warn("画像を変換できません(元画像を埋め込みます): #{data['fatal']}。" \
            'ruby-vips(gem)+libvips か Python 3+Pillow を導入してください')
    return nil
  end
  unless status.success? && data.is_a?(Array)
    hk_warn("画像の変換スクリプトが異常終了しました(元画像を埋め込みます): #{IMGCONV_SCRIPT}")
    return nil
  end
  data
rescue Errno::ENOENT
  hk_warn('画像を変換できません(元画像を埋め込みます): python3 が見つかりません。' \
          'ruby-vips(gem)+libvips か Python 3+Pillow を導入してください。--img-converter none で警告を抑止できます')
  nil
end
