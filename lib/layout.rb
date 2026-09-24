# frozen_string_literal: true

# 寸法計算(pt)。Typst 側の描画と同じ規則で高さ・幅を求め、はみ出しを警告する。

# 縦書き文字列の高さ。ベタ組み(1em 送り)。半角スペースは半分。
def text_height(str, fs)
  str.grapheme_clusters.sum { |c| c == ' ' ? fs / 2.0 : fs.to_f }
end

def elem_height(el)
  case el.type
  when :text  then text_height(el.text, el.fs)
  when :boxes then BOX_STROKE + el.cells.size * BOX_PITCH # = 30n - 0.75(n-1) mm
  when :image then IMAGE_SIZE
  when :space then el.mm * MM
  end
end

# 同一行内の隣接要素の隙間。space の前後は 0、それ以外は ELEM_GAPS の表による。
def elem_gap(a, b)
  return 0 if a.type == :space || b.type == :space

  ELEM_GAPS.fetch([a.type, b.type].sort, ELEM_GAP)
end

def line_height(line)
  els = line.elements
  els.sum { |e| elem_height(e) } + els.each_cons(2).sum { |a, b| elem_gap(a, b) }
end

# 行の種別。:section / :text(地の文のみ) / :boxes(記入欄・画像・スペースを含む)
def line_kind(line)
  return :section if line.kind == :section

  line.elements.all? { |e| e.type == :text } ? :text : :boxes
end

# 要素の幅(左右中央を揃える対象の幅)。space は幅を持たない。
def elem_width(el)
  case el.type
  when :text  then el.fs
  when :boxes then BOX_SIZE
  when :image then IMAGE_SIZE
  else 0
  end
end

# 行の本体幅 = 行内で最も幅の広い要素の幅。ふりがなは含めない。
def line_cw(line)
  [line.elements.map { |e| elem_width(e) }.max || 0, BODY_FS].max
end

# ふりがなによる右側への張り出し幅。記入欄は本体幅の中央に置かれるので、
# 記入欄の右端(= (cw + BOX_SIZE) / 2)から隙間とふりがなの分だけ右に出た量を本体幅から測る。
def line_ext(line)
  has_ruby = line.elements.any? { |e| e.type == :boxes && e.cells.any? { |c| !c.ruby.empty? } }
  return 0 unless has_ruby

  [(line_cw(line) + BOX_SIZE) / 2.0 + RUBY_GAP + RUBY_FS - line_cw(line), 0].max
end

def line_width(line)
  line_cw(line) + line_ext(line)
end

# 行間。a が前(右)の行、b が次(左)の行。
def line_gap(a, b)
  ka = line_kind(a)
  kb = line_kind(b)
  return LINE_GAP_SECTION if ka == :section        # セクションタイトルと次の行(2 行連続も含む)
  return LINE_GAP_BEFORE_SECTION if kb == :section # 前の行とセクションタイトル
  return LINE_GAP_TEXT if ka == :text && kb == :text
  return LINE_GAP_BOXES if ka == :boxes && kb == :boxes

  LINE_GAP_MIXED
end

def content_width(lines)
  lines.sum { |l| line_width(l) } + lines.each_cons(2).sum { |a, b| line_gap(a, b) }
end

def answer_text(page)
  return nil if page.answers.empty?

  ANSWER_PREFIX + page.answers.join(ANSWER_SEP)
end

# 行の内容の先頭部分(警告表示用)
def line_preview(line)
  s = line.elements.map do |e|
    case e.type
    when :text  then e.text
    when :boxes then '{}' * e.cells.size
    when :image then "![](#{e.path})"
    when :space then "{space: #{e.mm}}"
    end
  end.join
  s.size > 20 ? "#{s[0, 20]}…" : s
end

# ページ全体のはみ出しを検査して警告する。
def check_page(page)
  f = page.file
  if text_height(page.title, TITLE_FS) > AREA_H
    hk_warn("タイトルが下マージンを超えています(#{fmt_mm(text_height(page.title, TITLE_FS))} > #{fmt_mm(AREA_H)})", file: f)
  end
  desc_bottom = text_height(page.title, TITLE_FS) + TITLE_GAP + text_height(page.desc, DESC_FS)
  if desc_bottom > AREA_H
    hk_warn("問題説明文が下マージンを超えています(#{fmt_mm(desc_bottom)} > #{fmt_mm(AREA_H)})", file: f)
  end
  page.lines.each do |l|
    h = line_height(l)
    next if h <= AREA_H

    hk_warn("行が下マージンを超えています(#{fmt_mm(h)} > #{fmt_mm(AREA_H)}): #{line_preview(l)}", file: f, line: l.src_line)
  end
  w = content_width(page.lines)
  if w > CONTENT_W
    hk_warn("内容エリアが左マージンを超えています(#{fmt_mm(w)} > #{fmt_mm(CONTENT_W)})。行を減らすか行間を見直してください", file: f)
  end
  ans = answer_text(page)
  if ans && text_height(ans, ANSWER_FS) > AREA_H
    hk_warn("こっそり解答が上マージンを超えています(#{fmt_mm(text_height(ans, ANSWER_FS))} > #{fmt_mm(AREA_H)})", file: f)
  end
end
