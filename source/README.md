# How hoken-study.html is built

1. `parse.py` reads the practice test (converted to text with `pandoc test.docx -t plain -o out.txt`) and writes `qs2.json`.
2. `en0.json`–`en3.json` hold the English translations, trap words and trap types for each question.
3. `furi.py` adds hiragana (furigana) with the `fugashi` + `unidic-lite` tokenizer.
4. `vocab.py` writes `vocab.json` (word list).
5. `build.py template.html ../hoken-study.html` puts everything into the page.

```
pip install fugashi unidic-lite
python vocab.py && python build.py template.html ../hoken-study.html
```
