# hikarana

未就学児(4〜6歳想定)向けの，ひらがな／カタカナ練習問題(縦書き・マス目)ジェネレータ。
`md/` に置いた問題記述(front matter つき markdown)から Typst コードを生成し，A4 横・縦書きの PDF を 1 ファイルにまとめて出力します。

仕様の詳細は [CLAUDE.md](CLAUDE.md) を参照してください。

## 動作要件

- Ruby 4.0 系(標準ライブラリのみ)
- Typst 0.15 系
- 画像の縮小・JPEG 化用に，次のいずれか(無い場合は警告のうえ元画像をそのまま埋め込む)
    - ruby-vips(gem)+ libvips(推奨): `sudo apt install libvips42t64 && gem install ruby-vips`
    - Python 3 + Pillow(フォールバック)
- フォント(Typst から見えるようにインストール済みであること)
    - UDデジタル教科書体 ProN(`UDDigiKyokasho ProN`): 地の文・ヒント文字・ふりがな・こっそり解答
    - BIZ UDゴシック(`BIZ UDGothic`): タイトル・問題説明・セクションタイトル・問題種別番号
    - 縦書き字形(vert/vrt2)と JIS90 字体(jp90)を常に適用します。

## 使い方

```
ruby hikarana.rb            # md/*.md → tmp/hikarana.typ → out/hikarana.pdf
ruby hikarana.rb --only 0001,0002   # 指定番号のみ
ruby hikarana.rb --no-compile       # .typ 生成のみ
ruby hikarana.rb -h                 # オプション一覧
```

- `md/` の `nnnn.md` または `nnnn_description.md` を全て対象にし，ファイル名の ASCII 順にページを並べます。
- 画像は `img/` に置き，`![](ファイル名)` で `img/` からの相対パスを指定します。
- 画像は PDF 埋め込み時に 30mm×600dpi 相当(長辺 709px)の JPEG(品質 90)へ縮小されます。元画像は変更せず，変換結果は `tmp/imgcache/` にキャッシュされ，元画像が更新されると再変換されます。`--img-dpi` `--img-quality` で調整，`--img-converter vips|pillow|none` で変換器を固定，`--no-img-convert` で元画像のまま埋め込みます。
- 仕様外の記述やはみ出しは警告(`warning:`)として stderr に出力されます。内容の修正は問題作成者の責任です。

## 問題記述の例

```markdown
---
title: "ひらカナマスター"
number: "0001"
desc: "え や ぶんしょう と あうように わくのなかに じをかいてください。"
---

# Content

## ももたろう

なかまは
![](犬.png)
{}{}
と

![](猿.png)
{char: さ, ruby: さ}{ruby: る}
でした。

# Answer

- いぬ
- さる
```

- 空行で区切られた段落が縦 1 行になります。段落内の改行は前後を繋げます(スペースは入りません)。行末スペース 2 つで強制改行(次の縦行へ)できます。
- `{}` が記入欄 1 コマ。`{char: ア}` で薄い灰色のヒント文字，`{ruby: あ}` でコマ右側のふりがな，`{space: 10}` で 10mm の縦スペース(何も描かない)を指定します。
- 地の文では半角の英数字・記号は使えません(警告して無視)。全角の英数字は使えます。半角スペースは半分(0.5em)の空きとして描かれます。ただし地の文の先頭・末尾(記入欄や画像に隣接する箇所)の半角スペースは取り除かれます。
- `# Answer` の箇条書きは「こたえ：いぬ　さる」のように 1 行に連結され，ページ左下に 180 度回転して印字されます。

## ディレクトリ

| ディレクトリ | 内容 |
| --- | --- |
| `md/` | 問題記述(1 ファイル = 1 ページ) |
| `img/` | 画像(正方形 PNG 推奨) |
| `tmp/` | 中間生成の Typst ファイルと埋め込み用画像のキャッシュ(`imgcache/`) |
| `out/` | 生成した PDF |
| `lib/` | プログラム本体(config / parser / layout / typst / images / imgconv.py) |
