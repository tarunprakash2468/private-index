# Changelog

## [0.5.0](https://github.com/tarunprakash2468/private-index/compare/private-index-v0.4.0...private-index-v0.5.0) (2026-10-26)


### Features

* **crawler:** implement safe directory symlink traversal, cycle detection, and expanded folder exclusions ([64a322c](https://github.com/tarunprakash2468/private-index/commit/64a322ce457c3f03828a7c66433f0c318a82a447))
* **crawler:** safe directory symlink traversal, cycle detection, and expanded folder exclusions ([3fd2b20](https://github.com/tarunprakash2468/private-index/commit/3fd2b204cd9b1ba110f5b670ed4907615e1d8013))

## [0.4.0](https://github.com/tarunprakash2468/private-index/compare/private-index-v0.3.1...private-index-v0.4.0) (2026-10-25)


### Features

* **search,daemon:** add vector similarity threshold, confidence percentage display, and launchagent uninstall ([0ac97d3](https://github.com/tarunprakash2468/private-index/commit/0ac97d3194e1a35df05fd3b2096ca51628e4961c))

## [0.3.1](https://github.com/tarunprakash2468/private-index/compare/private-index-v0.3.0...private-index-v0.3.1) (2026-10-25)


### Bug Fixes

* **cli:** resolve bundle resources on symlinked installs and support subcommand help ([a321ec4](https://github.com/tarunprakash2468/private-index/commit/a321ec448be95c5eddee05de6817e3f7b3ac6e17))
* **formula:** correct v0.3.0 sha256 checksum and handle branch protection in sync step ([b3f24e6](https://github.com/tarunprakash2468/private-index/commit/b3f24e66468eb995f11bf064d8b85f5d9879ae9f))
* **model:** register new_ones and new_zeros torch ops and scope SPM resource to vocab.txt ([a4ad7cc](https://github.com/tarunprakash2468/private-index/commit/a4ad7ccd35820e7931c85fb7c1ba53bde3f55134))
* **model:** resolve new_ones op conversion in coremltools and scope SPM resources ([f8aea6b](https://github.com/tarunprakash2468/private-index/commit/f8aea6bc58a2b0f05109c45b2758e42f7fd56149))

## [0.3.0](https://github.com/tarunprakash2468/private-index/compare/private-index-v0.2.2...private-index-v0.3.0) (2026-10-25)


### Features

* **engine:** implement hybrid search combining SQLite FTS5 BM25 and vector embeddings via RRF ([#7](https://github.com/tarunprakash2468/private-index/issues/7)) ([13978c6](https://github.com/tarunprakash2468/private-index/commit/13978c6d4dce0dcb63c29b1c0d92ef04c4a33283))
* implement live folder watching and background sync across macOS, iOS, and CLI ([#6](https://github.com/tarunprakash2468/private-index/issues/6)) ([1b3f167](https://github.com/tarunprakash2468/private-index/commit/1b3f1670d330fffc4ab3dc9713f0b840daac7686))


### CI/CD & Automation

* **release:** enforce coreml model compilation ([#4](https://github.com/tarunprakash2468/private-index/issues/4)) ([d4daea3](https://github.com/tarunprakash2468/private-index/commit/d4daea38140881beba5614b5df0ce5e95513ab08))

## [0.2.2](https://github.com/tarunprakash2468/private-index/compare/private-index-v0.2.1...private-index-v0.2.2) (2026-10-25)


### Bug Fixes

* **package:** code sign macOS app bundle in release DMG ([b9ffad3](https://github.com/tarunprakash2468/private-index/commit/b9ffad34b371b3bd1bd2ba7aa1a8b8477b802577))


### CI/CD & Automation

* ensure release pipeline dynamically generates sha256 and syncs formula ([212c12c](https://github.com/tarunprakash2468/private-index/commit/212c12cd92971b1504849ddace4827766cf42860))

## [0.2.1](https://github.com/tarunprakash2468/private-index/compare/private-index-v0.2.0...private-index-v0.2.1) (2026-10-25)


### Bug Fixes

* **brew:** adjust test regex for ANSI escape sequences ([5d040e5](https://github.com/tarunprakash2468/private-index/commit/5d040e51690477294a691bea8a5d73ee4082c53c))
* bundle engine resources and prevent fatal error ([27e5829](https://github.com/tarunprakash2468/private-index/commit/27e5829bee2b10f916f89af7be1209312d9242e2))
* **engine:** ensure resource bundle locator resolves in CI tests ([e894aee](https://github.com/tarunprakash2468/private-index/commit/e894aeeb98028c2a5f91840774c68eff7b9d09ad))
* **formula:** update sha256 for 0.2.0 release ([8b4b800](https://github.com/tarunprakash2468/private-index/commit/8b4b800a96e5282018b4b77a6723b284b7f1140b))

## [0.2.0](https://github.com/tarunprakash2468/private-index/compare/private-index-v0.1.0...private-index-v0.2.0) (2026-10-25)


### Features

* add custom metallic pi app icons ([8f4d4e1](https://github.com/tarunprakash2468/private-index/commit/8f4d4e17d415e774c1c5f24ec4c83ed711250e66))
* add developer CLI, benchmarks, and CI ([acad239](https://github.com/tarunprakash2468/private-index/commit/acad239b3f3545de00a57259de5678cfde1f7711))
* add Homebrew tap formula and pi CLI alias ([df60776](https://github.com/tarunprakash2468/private-index/commit/df6077653fcd51029f9ab7a076d17026ff345c9a))
* add native PDFKit and Vision OCR extraction ([44d2d6e](https://github.com/tarunprakash2468/private-index/commit/44d2d6e321a2af5f030794cb58bf874e2a1477bc))
* add shell tab autocompletions for pi ([0429803](https://github.com/tarunprakash2468/private-index/commit/04298033f296aed577c7e6c8078e732d328b50ff))
* implement native iOS 17 SwiftUI application ([e6a0d33](https://github.com/tarunprakash2468/private-index/commit/e6a0d33047973c35e6aa72a887b3a40460f1c564))
* implement native macOS SwiftUI application ([29df2e9](https://github.com/tarunprakash2468/private-index/commit/29df2e9f6dae99baa4f5a27705c8bbecb7ddbfcd))
* implement tokenizer and indexing pipeline ([135fe64](https://github.com/tarunprakash2468/private-index/commit/135fe645bb7d668d9a037453902e04ccd152346a))
* scaffold engine, vector store, and CoreML ([452348b](https://github.com/tarunprakash2468/private-index/commit/452348b2fb81e83c71c5bf43883dc198c7f9ce17))


### Bug Fixes

* **cli:** resolve concurrency capture of limit ([43d36d8](https://github.com/tarunprakash2468/private-index/commit/43d36d8a1c14fdceae8e04df9e093705754f7c7c))
* **deps:** resolve Dependabot security alerts ([aaa907f](https://github.com/tarunprakash2468/private-index/commit/aaa907f07534b658ded804a9360e2cc355af7d40))
* **engine:** wrap macOS paths in os conditional ([e40bab9](https://github.com/tarunprakash2468/private-index/commit/e40bab90c7b2ba29c2d2b57b39edd5639472123e))
* **ios:** add macOS platform to iOS package ([1f8f8e5](https://github.com/tarunprakash2468/private-index/commit/1f8f8e537f86dd77db824b0b6d59b646347a42ee))


### Documentation

* separate user README and developer guide ([6a11956](https://github.com/tarunprakash2468/private-index/commit/6a1195658e55df6b6f8380f785e55ea204f3beef))


### Refactoring

* unify Core ML model loader across apps ([322f177](https://github.com/tarunprakash2468/private-index/commit/322f177f38088979b7bb11bf436ca6c13c1e50b6))


### CI/CD & Automation

* add automated model compilation pipeline ([1bdda79](https://github.com/tarunprakash2468/private-index/commit/1bdda7948b389fa1b8bacd454dd6ccf2bc53a1a4))
* add release workflow and TestFlight pipeline ([5f0260b](https://github.com/tarunprakash2468/private-index/commit/5f0260b77e5f39bff139e28043cd7192890e5747))
* automate releases via Google Release Please ([1065df5](https://github.com/tarunprakash2468/private-index/commit/1065df5539b26c771fc5a37f31f50975b2dc4dc8))
* configure dependabot for automated updates ([bd1b5bb](https://github.com/tarunprakash2468/private-index/commit/bd1b5bba0f143298403b1ee460c1a3fc56a4d1d1))
* pass iphonesimulator sdk to swift build ([9469fa1](https://github.com/tarunprakash2468/private-index/commit/9469fa145b082ff22cbfd42af74f843412a995d7))
