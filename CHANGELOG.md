# Changelog

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
