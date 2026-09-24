# frozen_string_literal: true

# 問題記述言語(front matter つき markdown)の解析。1 ファイル = 1 ページ。

require 'strscan'

# 1 ページ分の問題
Page = Struct.new(:file, :number, :title, :desc, :lines, :answers, keyword_init: true)
# 内容エリアの 1 行(縦 1 行)。kind は :section(セクションタイトル) か :normal。
Line = Struct.new(:kind, :elements, :src_line, keyword_init: true)
# 行内の要素。type は :text / :boxes / :image / :space。
#   :text  … text(文字列), fs(文字サイズ pt), font(:body / :title)
#   :boxes … cells(Cell の配列。連続する記入欄をまとめたもの)
#   :image … path(img/ からの相対パス), exists(ファイルの有無), embed(PDF に埋め込むファイルの絶対パス)
#   :space … mm(縦スペースの高さ mm)
Elem = Struct.new(:type, :text, :fs, :font, :cells, :path, :exists, :mm, :embed, keyword_init: true)
# 記入欄 1 コマ。char はヒント文字(薄い灰色)、ruby はふりがな。いずれも無ければ ""。
Cell = Struct.new(:char, :ruby, keyword_init: true)

class MdParser
  IMG_RE = /!\[[^\]]*\]\(([^)]*)\)/
  BOX_RE = /\{([^{}]*)\}/
  HEADING_RE = /\A(\#{1,6})\s*(\S.*?)\s*\#*\s*\z/
  BULLET_RE  = /\A\s*(?:[-*+]|\d+\.)\s+(.*?)\s*\z/
  FM_KEYS = %w[title number desc].freeze
  BOX_KEYS = %w[char ruby space].freeze

  def initialize(path, img_dir:)
    @path = path
    @img_dir = img_dir
    @lines = []      # 内容エリアの行
    @answers = []
    @para = []       # 段落バッファ: [[文字列, 行番号], ...](強制改行で区切られた縦行ごと)
    @para_open = false
  end

  def parse
    src = File.read(@path, encoding: 'UTF-8').delete_prefix("﻿").split(/\r?\n/, -1)
    fm, body_start = parse_front_matter(src)
    parse_body(src, body_start)

    number = fm['number'] || File.basename(@path)[MD_FILE_RE, 1]
    unless number&.match?(/\A\d{4}\z/)
      warn_at("問題種別番号は算用数字4桁で指定してください: #{number.inspect}")
      number = number.to_s
    end

    Page.new(file: @path, number: number,
             title: fm.key?('title') ? filter_text(fm['title'], 1) : DEFAULT_TITLE,
             desc: fm.key?('desc') ? filter_text(fm['desc'], 1) : DEFAULT_DESC,
             lines: @lines, answers: @answers)
  end

  private

  def warn_at(msg, line: nil)
    hk_warn(msg, file: @path, line: line)
  end

  # ---- front matter -------------------------------------------------------

  # 先頭の "---" ... "---" を key: value として読む。戻り値は [ハッシュ, 本文開始行(0 始まり)]。
  def parse_front_matter(src)
    fm = {}
    return [fm, 0] unless src[0]&.match?(/\A---\s*\z/)

    close = (1...src.size).find { |i| src[i].match?(/\A---\s*\z/) }
    unless close
      warn_at('front matter が閉じていません(--- が見つかりません)。無視します', line: 1)
      return [fm, 0]
    end

    (1...close).each do |i|
      s = src[i]
      next if s.strip.empty?

      m = s.match(/\A([A-Za-z_]\w*)\s*:\s*(.*?)\s*\z/)
      unless m
        warn_at("front matter を解釈できません: #{s}", line: i + 1)
        next
      end
      key = m[1].downcase
      unless FM_KEYS.include?(key)
        warn_at("front matter の不明なキーです(無視します): #{m[1]}", line: i + 1)
        next
      end
      fm[key] = unquote(m[2])
    end
    [fm, close + 1]
  end

  def unquote(v)
    v = v.strip
    if (m = v.match(/\A"(.*)"\z/m) || v.match(/\A'(.*)'\z/m))
      m[1]
    else
      v
    end
  end

  # ---- 本文 -----------------------------------------------------------------

  def parse_body(src, start)
    state = :preamble # :preamble(# Content より前) / :content / :answer / :ignore(不明な第1レベル)
    preamble_warned = false

    src.each_with_index do |raw, idx|
      next if idx < start

      lineno = idx + 1
      s = raw.rstrip

      if (m = s.match(HEADING_RE))
        flush_para
        level = m[1].size
        text = m[2]
        case level
        when 1
          case text.strip.downcase
          when 'content' then state = :content
          when 'answer'  then state = :answer
          else
            warn_at("不明な第1レベルタイトルです(以降 Content/Answer まで無視します): # #{text}", line: lineno)
            state = :ignore
          end
        when 2
          if state == :content
            t = filter_text(text, lineno)
            @lines << Line.new(kind: :section, src_line: lineno,
                               elements: [Elem.new(type: :text, text: t, fs: SECTION_FS, font: :title)])
          elsif state != :ignore
            warn_at("セクションタイトルは # Content 内にのみ書けます(無視します): ## #{text}", line: lineno)
          end
        else
          warn_at("第#{level}レベルのタイトルは仕様外です(無視します): #{s}", line: lineno) unless state == :ignore
        end
        next
      end

      if s.strip.empty?
        flush_para
        next
      end

      if (m = s.match(BULLET_RE))
        flush_para
        case state
        when :answer
          t = filter_text(m[1], lineno).strip
          @answers << t unless t.empty?
        when :ignore then nil
        else
          warn_at("箇条書きは # Answer 内にのみ書けます(無視します): #{s}", line: lineno)
        end
        next
      end

      case state
      when :content
        add_para_line(raw, lineno)
      when :answer
        warn_at("# Answer 内の箇条書き以外の行は無視します: #{s}", line: lineno)
      when :preamble
        unless preamble_warned
          warn_at('# Content より前の本文は無視します', line: lineno)
          preamble_warned = true
        end
      end
    end
    flush_para
  end

  # 段落に 1 行を追加する。1 回の改行は前後を繋げ、行末スペース 2 つは強制改行(縦行を分ける)。
  def add_para_line(raw, lineno)
    hard_break = raw.match?(/ {2,}\z/) # rstrip 前の生の行で判定
    text = raw.strip
    if @para_open
      @para.last[0] << text
    else
      @para << [+text, lineno]
      @para_open = true
    end
    @para_open = false if hard_break
  end

  def flush_para
    @para.each do |text, lineno|
      elems = parse_inline(text, lineno)
      @lines << Line.new(kind: :normal, elements: elems, src_line: lineno) unless elems.empty?
    end
    @para = []
    @para_open = false
  end

  # ---- インライン要素 -----------------------------------------------------

  # 1 縦行分の文字列を要素列(地の文 / 記入欄 / 画像 / スペース)に分解する。
  def parse_inline(str, lineno)
    raw = []
    buf = +''
    ss = StringScanner.new(str)
    until ss.eos?
      if ss.scan(IMG_RE)
        raw << text_elem(buf, lineno) unless buf.empty?
        buf = +''
        raw << image_elem(ss[1], lineno)
      elsif ss.scan(BOX_RE)
        raw << text_elem(buf, lineno) unless buf.empty?
        buf = +''
        e = box_elem(ss[1], lineno)
        raw << e if e
      else
        buf << ss.getch
      end
    end
    raw << text_elem(buf, lineno) unless buf.empty?

    # 同種の隣接要素をまとめる → 地の文の端の半角スペースを落とす → 空になった地の文を除いて再度まとめる
    elems = merge_adjacent(raw.compact)
    elems.each { |e| e.text = e.text.gsub(/\A +| +\z/, '') if e.type == :text }
    elems.reject! { |e| e.type == :text && e.text.empty? }
    merge_adjacent(elems)
  end

  def merge_adjacent(elems)
    out = []
    elems.each do |e|
      prev = out.last
      if prev && prev.type == e.type && e.type == :text
        prev.text = prev.text + e.text
      elsif prev && prev.type == e.type && e.type == :boxes
        prev.cells.concat(e.cells)
      else
        out << e
      end
    end
    out
  end

  def text_elem(buf, lineno)
    Elem.new(type: :text, text: filter_text(buf, lineno), fs: BODY_FS, font: :body)
  end

  def image_elem(path, lineno)
    path = path.strip
    if path.empty?
      warn_at('画像のパスが空です(空の画像エリアにします)', line: lineno)
      return Elem.new(type: :image, path: '', exists: false)
    end
    # img/ からの相対パスのみ許す(サブディレクトリは可)。絶対パスや ".." による外部参照は不可。
    if path.start_with?('/') || path.split('/').include?('..')
      warn_at("画像は img/ からの相対パスで指定してください(空の画像エリアにします): #{path}", line: lineno)
      return Elem.new(type: :image, path: path, exists: false)
    end
    exists = File.file?(File.join(@img_dir, path))
    warn_at("画像ファイルが見つかりません(空の画像エリアにします): #{File.join(@img_dir, path)}", line: lineno) unless exists
    Elem.new(type: :image, path: path, exists: exists)
  end

  # "{...}" の中身から記入欄(またはスペース)を作る。無効なスペース指定は nil を返す。
  def box_elem(inner, lineno)
    inner = inner.strip
    return Elem.new(type: :boxes, cells: [Cell.new(char: '', ruby: '')]) if inner.empty?

    pairs = inner.scan(/([A-Za-z_]\w*)\s*[:：]\s*("[^"]*"|'[^']*'|[^,，]*)/)
    if pairs.empty?
      warn_at("記入欄の指定を解釈できません(通常の記入欄にします): {#{inner}}", line: lineno)
      return Elem.new(type: :boxes, cells: [Cell.new(char: '', ruby: '')])
    end

    opts = {}
    pairs.each do |k, v|
      key = k.downcase
      if BOX_KEYS.include?(key)
        opts[key] = unquote(v)
      else
        warn_at("記入欄の不明なキーです(無視します): #{k}", line: lineno)
      end
    end

    if opts.key?('space')
      warn_at('space と char/ruby は同時に指定できません(space のみ使います)', line: lineno) if opts.key?('char') || opts.key?('ruby')
      mm = begin
        Float(opts['space'].tr('０-９．', '0-9.'))
      rescue ArgumentError, TypeError
        nil
      end
      if mm.nil? || mm.negative?
        warn_at("space の幅(mm)を解釈できません(無視します): #{opts['space'].inspect}", line: lineno)
        return nil
      end
      return Elem.new(type: :space, mm: mm)
    end

    char = filter_text(opts['char'].to_s, lineno).strip
    if char.grapheme_clusters.size > 1
      warn_at("char には 1 文字のみ指定できます(先頭の文字を使います): #{char}", line: lineno)
      char = char.grapheme_clusters.first
    end
    ruby = filter_text(opts['ruby'].to_s, lineno).strip
    Elem.new(type: :boxes, cells: [Cell.new(char: char, ruby: ruby)])
  end

  # ---- 文字のフィルタ -------------------------------------------------------

  # 半角英数字・半角記号は使用不可(警告して無視)。半角スペースは残す(半角分の空きになる)。
  # markdown の強調記号(* _)は仕様外として警告のうえ取り除く。
  def filter_text(str, lineno)
    if str.match?(/[*_]/)
      warn_at('強調は仕様外です(記号を無視します)', line: lineno)
      str = str.delete('*_')
    end
    alnum = []
    other = []
    out = +''
    str.each_char do |c|
      if c.ord >= 0x80
        out << c
      elsif c.match?(/[0-9A-Za-z]/)
        alnum << c
      elsif c.match?(/\s/)
        out << ' '
      else
        other << c
      end
    end
    warn_at("半角英数字は使用できません(無視します): #{alnum.join}", line: lineno) unless alnum.empty?
    warn_at("半角記号は使用できません(無視します): #{other.join}", line: lineno) unless other.empty?
    out
  end
end
