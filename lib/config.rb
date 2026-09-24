# frozen_string_literal: true

# 設定(定数)。hikarana.rb から最初に読み込まれる。
# 長さは原則 pt で扱う(Typst へ出力するときに単位を付ける)。

MM = 72.0 / 25.4 # 1mm を pt に換算する係数

# ---- フォント ----------------------------------------------------------
FONT_BODY  = 'UDDigiKyokasho ProN' # 地の文・記入欄のヒント/ふりがな・こっそり解答
FONT_TITLE = 'BIZ UDGothic'        # タイトル・問題説明・セクションタイトル・問題種別番号
# 縦書き字形(vert/vrt2)と JIS90 字体(jp90)。両フォントとも対応している。
FONT_FEATURES = %w[vert vrt2 jp90].freeze

# ---- 用紙 ---------------------------------------------------------------
PAGE_W = 297 * MM # A4 landscape
PAGE_H = 210 * MM
MARGIN = 10 * MM
AREA_W = PAGE_W - 2 * MARGIN # 印字可能幅(277mm)
AREA_H = PAGE_H - 2 * MARGIN # 印字可能高さ(190mm)

# ---- タイトル / 問題説明 / 問題種別番号 ----------------------------------
TITLE_FS      = 16   # タイトル(pt)
DESC_FS       = 12   # 問題説明(pt)
NUMBER_FS     = 8    # 問題種別番号(pt)
TITLE_GAP     = 20 * MM # タイトル → 問題説明エリアの空き
DESC_TOP      = 30 * MM # 問題説明の上端(上マージン端から)
DESC_GAP      = 20 * MM # 問題説明エリア → 内容エリアの空き
DEFAULT_TITLE = 'ひらカナマスター'
DEFAULT_DESC  = 'え や ぶんしょう と あうように わくのなかに じをかいてください。'

# 内容エリアの右端位置(上マージン端の右端からの距離)
CONTENT_RIGHT_OFFSET = TITLE_FS + TITLE_GAP + DESC_FS + DESC_GAP
CONTENT_W = AREA_W - CONTENT_RIGHT_OFFSET # 内容エリアの使える幅

# ---- 内容エリア -----------------------------------------------------------
SECTION_FS = 14 # セクションタイトル(pt)
BODY_FS    = 12 # 地の文(pt)
RUBY_FS    = 9  # ふりがな(pt)
RUBY_GAP   = 3  # 記入欄とふりがなの隙間(pt)
HINT_EM    = 24 * MM # ヒント文字の em ボックス(mm)
HINT_LUMA  = 200     # ヒント文字の色(luma。大きいほど薄い)

BOX_SIZE   = 30 * MM   # 記入欄 1 コマの外寸(正方形)
BOX_STROKE = 0.75 * MM # コマの枠線(実線・黒)
GUIDE_STROKE = 0.5 * MM # 分割線(点線・灰)
GUIDE_LUMA   = 150
BOX_PITCH  = BOX_SIZE - BOX_STROKE # 連続する記入欄の境界線どうしの間隔
IMAGE_SIZE = 30 * MM   # 画像エリア(正方形)

ELEM_GAP = 12 # 同一行内の要素(文字/記入欄/画像)どうしの隙間(pt)。space の前後は 0。

# 行間(pt)
LINE_GAP_SECTION = 18      # セクションタイトルと他の行
LINE_GAP_TEXT    = 12      # 地の文のみの行どうし
LINE_GAP_MIXED   = 18      # 地の文のみの行と記入欄/画像のある行
LINE_GAP_BOXES   = 20 * MM # 記入欄/画像のある行どうし

# ---- こっそり解答 ---------------------------------------------------------
ANSWER_FS     = 9
ANSWER_PREFIX = 'こたえ：'
ANSWER_SEP    = '　'

# ---- ファイル ---------------------------------------------------------------
MD_FILE_RE = /\A(\d{4})(?:_[^\/]*)?\.md\z/ # "nnnn.md" または "nnnn_description.md"
DEFAULT_MD_DIR  = 'md'
DEFAULT_IMG_DIR = 'img'
DEFAULT_TMP_DIR = 'tmp'
DEFAULT_OUTPUT  = 'out/hikarana.pdf'
BASENAME        = 'hikarana'

# ---- 警告 -------------------------------------------------------------------
$hk_warnings = 0

# 警告を stderr に出力する。file/line は分かる場合のみ付ける。
def hk_warn(msg, file: nil, line: nil)
  $hk_warnings += 1
  loc = file ? "#{file}#{line ? ":#{line}" : ''}: " : ''
  warn "warning: #{loc}#{msg}"
end

def fmt_mm(pt)
  format('%.1fmm', pt / MM)
end
