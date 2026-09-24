# frozen_string_literal: true

# Typst コードの生成。縦書きは 1 文字ずつ 1em 正方形の箱に入れて縦に積む。

def typ_str(s)
  '"' + s.to_s.gsub('\\', '\\\\\\\\').gsub('"', '\\"') + '"'
end

def typ_pt(pt)
  format('%.4fpt', pt).sub(/\.?0+pt\z/, 'pt')
end

# 前文: ページ設定・フォント・描画関数
def typ_preamble
  feats = FONT_FEATURES.map { |f| typ_str(f) }.join(', ')
  <<~TYP
    // 自動生成ファイル (hikarana.rb) — 直接編集しないでください。
    #set page(paper: "a4", flipped: true, margin: #{typ_pt(MARGIN)})
    // top-edge/bottom-edge を ascender/descender にすると、行の高さが
    // ちょうど 1em(全角の em ボックス)になり、1em の箱に文字が収まる。
    // OpenType 機能は set ルールと呼び出し側で結合されるため、ここでは設定せず
    // 描画関数側で明示的に渡す(横書きの番号に縦書き字形が掛からないように)。
    #set text(font: #{typ_str(FONT_BODY)}, lang: "ja", top-edge: "ascender", bottom-edge: "descender")
    #set par(leading: 0pt, spacing: 0pt)
    // 縦書き字形(vert/vrt2)と JIS90 字体(jp90)。横書き(問題種別番号)は jp90 のみ。
    #let VFEATS = (#{feats},)
    #let HFEATS = ("jp90",)

    #let BODY   = #{typ_str(FONT_BODY)}
    #let GOTHIC = #{typ_str(FONT_TITLE)}

    #let TITLEFS   = #{typ_pt(TITLE_FS)}
    #let DESCFS    = #{typ_pt(DESC_FS)}
    #let NUMBERFS  = #{typ_pt(NUMBER_FS)}
    #let TITLEGAP  = #{typ_pt(TITLE_GAP)}
    #let CONTENTOFF = #{typ_pt(CONTENT_RIGHT_OFFSET)}
    #let ANSFS     = #{typ_pt(ANSWER_FS)}

    #let BOXSIZE   = #{typ_pt(BOX_SIZE)}
    #let BOXSTROKE = #{typ_pt(BOX_STROKE)}
    #let BOXPITCH  = BOXSIZE - BOXSTROKE
    #let IMGSIZE   = #{typ_pt(IMAGE_SIZE)}
    #let HINTEM    = #{typ_pt(HINT_EM)}
    #let RUBYFS    = #{typ_pt(RUBY_FS)}
    #let RUBYGAP   = #{typ_pt(RUBY_GAP)}

    #let bstroke = BOXSTROKE + black
    #let gstroke = (paint: luma(#{GUIDE_LUMA}), thickness: #{typ_pt(GUIDE_STROKE)}, dash: "dotted")
    #let hintfill = luma(#{HINT_LUMA})

    // 縦書き文字列の高さ(半角スペースは半分)
    #let vheight(s, size) = s.clusters().map(c => if c == " " { size / 2 } else { size }).sum(default: 0pt)

    // 縦書き文字列。1 文字ずつ size × size の箱に入れて上から積む(ベタ組み)。
    // 文字は箱の左端に原点を合わせる(左揃え)。句読点や括弧(。、，：「」)は縦書き字形でも
    // 横方向の送り幅が 0.5em で、中央揃えにすると原点が 0.25em 右へ寄ってしまう。
    // 輪郭は原点基準で全角の枡の正しい位置に描かれているので、左揃えで正しく収まる。
    #let vtext(s, size, font, fill: black, weight: "regular") = stack(dir: ttb,
      ..s.clusters().map(c =>
        if c == " " { box(width: size, height: size / 2) }
        else { box(width: size, height: size, align(left + horizon,
          text(font: font, size: size, fill: fill, weight: weight, features: VFEATS, c))) }))

    // 記入欄。cells は (char: "", ruby: "") の配列。連続するコマは境界線を共有する。
    #let boxes(cells) = {
      let n = cells.len()
      let h = BOXSTROKE + n * BOXPITCH
      block(width: BOXSIZE, height: h, {
        // 外枠(線は境界に中心が乗るので、線幅の半分だけ内側に寄せて外寸を合わせる)
        place(top + left, dx: BOXSTROKE / 2, dy: BOXSTROKE / 2,
          rect(width: BOXSIZE - BOXSTROKE, height: h - BOXSTROKE, stroke: bstroke))
        for (i, c) in cells.enumerate() {
          let ty = BOXSTROKE / 2 + i * BOXPITCH // 上側の境界線の中心
          let cy = ty + BOXPITCH / 2            // コマの中心
          if i > 0 {
            place(top + left, dx: BOXSTROKE / 2, dy: ty,
              line(length: BOXSIZE - BOXSTROKE, stroke: bstroke))
          }
          if c.char == "" {
            // 分割線(点線)。ヒント文字があるコマには描かない。
            place(top + left, dx: BOXSIZE / 2, dy: ty + BOXSTROKE / 2,
              line(angle: 90deg, length: BOXPITCH - BOXSTROKE, stroke: gstroke))
            place(top + left, dx: BOXSTROKE / 2, dy: cy,
              line(length: BOXSIZE - BOXSTROKE, stroke: gstroke))
          } else {
            place(top + left, dx: BOXSIZE / 2 - HINTEM / 2, dy: cy - HINTEM / 2,
              box(width: HINTEM, height: HINTEM,
                align(left + horizon, text(font: BODY, size: HINTEM, fill: hintfill, features: VFEATS, c.char))))
          }
          if c.ruby != "" {
            let rh = vheight(c.ruby, RUBYFS)
            place(top + left, dx: BOXSIZE + RUBYGAP, dy: cy - rh / 2, vtext(c.ruby, RUBYFS, BODY))
          }
        }
      })
    }

    // 画像(正方形エリアに収まるよう縮小。枠なし)
    #let img(path) = block(width: IMGSIZE, height: IMGSIZE,
      align(center + horizon, image(path, width: IMGSIZE, height: IMGSIZE, fit: "contain")))
    // 画像ファイルが無いときの代替(薄い破線の枠)
    #let noimg = block(width: IMGSIZE, height: IMGSIZE,
      stroke: (paint: luma(180), thickness: 0.3mm, dash: "dashed"))

    // 縦 1 行。cw は本体幅(要素をこの幅の中央に揃える)、ext はふりがなの張り出し幅。
    // items には要素(content)と隙間(length)が混在する。
    #let vline(cw, ext, items) = block(width: cw + ext, stack(dir: ttb,
      ..items.map(it => if type(it) == length { it } else { block(width: cw, align(center, it)) })))

    // 1 ページ
    #let hkpage(title, desc, number, content, answer) = block(width: 100%, height: 100%, {
      // タイトル(Bold)は最右上。問題説明はその下 20mm、タイトル列の中央に揃える。
      place(top + right, vtext(title, TITLEFS, GOTHIC, weight: "bold"))
      place(top + right, dx: -(TITLEFS - DESCFS) / 2, dy: vheight(title, TITLEFS) + TITLEGAP,
        vtext(desc, DESCFS, GOTHIC))
      place(bottom + right, text(font: GOTHIC, size: NUMBERFS, features: HFEATS, number))
      if content != none { place(top + right, dx: -CONTENTOFF, content) }
      // こっそり解答: 左下に 180 度回転(行も文字も反転)で置く
      if answer != none { place(bottom + left, rotate(180deg, reflow: true, vtext(answer, ANSFS, BODY))) }
    })
  TYP
end

def typ_elem(el)
  case el.type
  when :text
    # セクションタイトル(font: :title)は BIZ UDゴシックの Bold
    el.font == :title ? "vtext(#{typ_str(el.text)}, #{typ_pt(el.fs)}, GOTHIC, weight: \"bold\")" \
                      : "vtext(#{typ_str(el.text)}, #{typ_pt(el.fs)}, BODY)"
  when :boxes
    cells = el.cells.map { |c| "(char: #{typ_str(c.char)}, ruby: #{typ_str(c.ruby)})" }
    "boxes((#{cells.join(', ')},))"
  when :image
    el.exists && el.embed ? "img(#{typ_str(el.embed)})" : 'noimg'
  when :space
    format('%.3fmm', el.mm)
  end
end

def typ_line(line)
  items = []
  line.elements.each_with_index do |e, i|
    items << typ_pt(elem_gap(line.elements[i - 1], e)) if i.positive?
    items << typ_elem(e)
  end
  "vline(#{typ_pt(line_cw(line))}, #{typ_pt(line_ext(line))}, (#{items.join(', ')},))"
end

def typ_content(lines)
  return 'none' if lines.empty?

  parts = []
  lines.each_with_index do |l, i|
    parts << typ_pt(line_gap(lines[i - 1], l)) if i.positive?
    parts << typ_line(l)
  end
  "stack(dir: rtl,\n    #{parts.join(",\n    ")})"
end

# 画像は el.embed の絶対パスで参照する(Typst のルートは / で実行する)
def typ_page(page)
  ans = answer_text(page)
  <<~TYP
    // #{page.file}
    #hkpage(#{typ_str(page.title)}, #{typ_str(page.desc)}, #{typ_str(page.number)},
      #{typ_content(page.lines)},
      #{ans ? typ_str(ans) : 'none'})
  TYP
end

def build_typst(pages)
  typ_preamble + "\n" + pages.map { |p| typ_page(p) }.join("\n#pagebreak(weak: true)\n\n")
end
