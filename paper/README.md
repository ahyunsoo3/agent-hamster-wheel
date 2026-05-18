# Paper Draft

This directory contains an arXiv-ready LaTeX draft for the branch comparison study.

## Files

- `main.tex` - manuscript source.
- `references.bib` - BibTeX references.

## Build

From this directory:

```bash
pdflatex main
bibtex main
pdflatex main
pdflatex main
```

If `latexmk` is installed:

```bash
latexmk -pdf main.tex
```

## arXiv Upload

Upload `main.tex` and `references.bib` together. The source uses the standard `article` class and common TeX packages (`array`, `booktabs`, `geometry`, `hyperref`, `pgfplots`, and `url`) to keep the submission portable while rendering the benchmark graph directly from LaTeX.
