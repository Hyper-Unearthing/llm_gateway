# Changelog

## [v0.8.0](https://github.com/Hyper-Unearthing/llm_gateway/tree/v0.8.0) (2026-06-06)

[Full Changelog](https://github.com/Hyper-Unearthing/llm_gateway/compare/v0.7.0...v0.8.0)

**Merged pull requests:**

- feat: create server proxy and corresponding client [\#89](https://github.com/Hyper-Unearthing/llm_gateway/pull/89) ([billybonks](https://github.com/billybonks))

## [v0.7.0](https://github.com/Hyper-Unearthing/llm_gateway/tree/v0.7.0) (2026-06-03)

[Full Changelog](https://github.com/Hyper-Unearthing/llm_gateway/compare/v0.6.0...v0.7.0)

**Merged pull requests:**

- feat: add agent harness [\#88](https://github.com/Hyper-Unearthing/llm_gateway/pull/88) ([billybonks](https://github.com/billybonks))
- refactor: prompt to use modern patterns [\#87](https://github.com/Hyper-Unearthing/llm_gateway/pull/87) ([billybonks](https://github.com/billybonks))
- feat: change our utils to follow actie support style [\#85](https://github.com/Hyper-Unearthing/llm_gateway/pull/85) ([billybonks](https://github.com/billybonks))
- feat: add reasoning level as soemthing configurable in prompt [\#83](https://github.com/Hyper-Unearthing/llm_gateway/pull/83) ([billybonks](https://github.com/billybonks))
- feat: add support for code execution tool [\#79](https://github.com/Hyper-Unearthing/llm_gateway/pull/79) ([billybonks](https://github.com/billybonks))

## [v0.6.0](https://github.com/Hyper-Unearthing/llm_gateway/tree/v0.6.0) (2026-05-27)

[Full Changelog](https://github.com/Hyper-Unearthing/llm_gateway/compare/v0.5.0...v0.6.0)

**Closed issues:**

- issues with token normalization [\#75](https://github.com/Hyper-Unearthing/llm_gateway/issues/75)
- Add normalized token usage fields for streamed responses [\#72](https://github.com/Hyper-Unearthing/llm_gateway/issues/72)
- Add timestamp metadata to messages [\#70](https://github.com/Hyper-Unearthing/llm_gateway/issues/70)
- Build final AssistantMessage in stream pipeline and include it on message\_end [\#69](https://github.com/Hyper-Unearthing/llm_gateway/issues/69)
- Expose finalized content on stream \_end events [\#68](https://github.com/Hyper-Unearthing/llm_gateway/issues/68)
- Add accumulated AssistantMessage partials to stream events [\#66](https://github.com/Hyper-Unearthing/llm_gateway/issues/66)
- 1.0 [\#37](https://github.com/Hyper-Unearthing/llm_gateway/issues/37)

**Merged pull requests:**

- Improve token normalization [\#78](https://github.com/Hyper-Unearthing/llm_gateway/pull/78) ([billybonks](https://github.com/billybonks))
- fix\(tests\): the hand off tests were totally fake, now they work [\#77](https://github.com/Hyper-Unearthing/llm_gateway/pull/77) ([billybonks](https://github.com/billybonks))
- Improve message event metadata and helpers [\#74](https://github.com/Hyper-Unearthing/llm_gateway/pull/74) ([billybonks](https://github.com/billybonks))
- fix: update migration guide [\#73](https://github.com/Hyper-Unearthing/llm_gateway/pull/73) ([billybonks](https://github.com/billybonks))
- feat: add partial message as part of streaming events [\#67](https://github.com/Hyper-Unearthing/llm_gateway/pull/67) ([billybonks](https://github.com/billybonks))
- docs: add migration guide for upcomming version [\#65](https://github.com/Hyper-Unearthing/llm_gateway/pull/65) ([billybonks](https://github.com/billybonks))
- Decouple model selection from provider auth configuration [\#64](https://github.com/Hyper-Unearthing/llm_gateway/pull/64) ([billybonks](https://github.com/billybonks))
- burn: support for legacy provider keys [\#63](https://github.com/Hyper-Unearthing/llm_gateway/pull/63) ([billybonks](https://github.com/billybonks))
- docs: add docs about options for stream method [\#62](https://github.com/Hyper-Unearthing/llm_gateway/pull/62) ([billybonks](https://github.com/billybonks))

## [v0.5.0](https://github.com/Hyper-Unearthing/llm_gateway/tree/v0.5.0) (2026-05-20)

[Full Changelog](https://github.com/Hyper-Unearthing/llm_gateway/compare/v0.4.0...v0.5.0)

**Merged pull requests:**

- Refactor stream mapper accumulation [\#61](https://github.com/Hyper-Unearthing/llm_gateway/pull/61) ([billybonks](https://github.com/billybonks))
- feat\(groq\): add stream support for groq [\#60](https://github.com/Hyper-Unearthing/llm_gateway/pull/60) ([billybonks](https://github.com/billybonks))
- test\(feat\): allow options to be passed in model pairs [\#59](https://github.com/Hyper-Unearthing/llm_gateway/pull/59) ([billybonks](https://github.com/billybonks))
- Focus streaming and Claude client tests [\#58](https://github.com/Hyper-Unearthing/llm_gateway/pull/58) ([billybonks](https://github.com/billybonks))
- feat\(test\): automatically delete unused vcrs [\#57](https://github.com/Hyper-Unearthing/llm_gateway/pull/57) ([billybonks](https://github.com/billybonks))
- refactor: handoff test [\#56](https://github.com/Hyper-Unearthing/llm_gateway/pull/56) ([billybonks](https://github.com/billybonks))
- Refactor/options clients [\#55](https://github.com/Hyper-Unearthing/llm_gateway/pull/55) ([billybonks](https://github.com/billybonks))
- burn: all the old code [\#54](https://github.com/Hyper-Unearthing/llm_gateway/pull/54) ([billybonks](https://github.com/billybonks))
- test: only skip actual auth errors [\#53](https://github.com/Hyper-Unearthing/llm_gateway/pull/53) ([billybonks](https://github.com/billybonks))
- test: dont try refresh token when using vcr only when regenerating [\#52](https://github.com/Hyper-Unearthing/llm_gateway/pull/52) ([billybonks](https://github.com/billybonks))

## [v0.4.0](https://github.com/Hyper-Unearthing/llm_gateway/tree/v0.4.0) (2026-05-17)

[Full Changelog](https://github.com/Hyper-Unearthing/llm_gateway/compare/v0.3.0...v0.4.0)

**Merged pull requests:**

- docs: update docs new code [\#51](https://github.com/Hyper-Unearthing/llm_gateway/pull/51) ([billybonks](https://github.com/billybonks))
- test: rework live tests to use vcr [\#50](https://github.com/Hyper-Unearthing/llm_gateway/pull/50) ([billybonks](https://github.com/billybonks))
- refactor: update provider keys [\#49](https://github.com/Hyper-Unearthing/llm_gateway/pull/49) ([billybonks](https://github.com/billybonks))
- Refactor/major internal organisation [\#48](https://github.com/Hyper-Unearthing/llm_gateway/pull/48) ([billybonks](https://github.com/billybonks))
- cross provider handoff support [\#47](https://github.com/Hyper-Unearthing/llm_gateway/pull/47) ([billybonks](https://github.com/billybonks))
- Refactor provider usage and especially oauth [\#46](https://github.com/Hyper-Unearthing/llm_gateway/pull/46) ([billybonks](https://github.com/billybonks))
- Refactor/options [\#45](https://github.com/Hyper-Unearthing/llm_gateway/pull/45) ([billybonks](https://github.com/billybonks))
- fix: map content blocks in tools as well [\#44](https://github.com/Hyper-Unearthing/llm_gateway/pull/44) ([billybonks](https://github.com/billybonks))
- Streaming support [\#43](https://github.com/Hyper-Unearthing/llm_gateway/pull/43) ([billybonks](https://github.com/billybonks))
- feat: try to simplify api and provider combination [\#42](https://github.com/Hyper-Unearthing/llm_gateway/pull/42) ([billybonks](https://github.com/billybonks))
- feat: add reasoning effort parameter [\#41](https://github.com/Hyper-Unearthing/llm_gateway/pull/41) ([billybonks](https://github.com/billybonks))
- Feat/backport streaming [\#40](https://github.com/Hyper-Unearthing/llm_gateway/pull/40) ([billybonks](https://github.com/billybonks))
- fix: cache control [\#39](https://github.com/Hyper-Unearthing/llm_gateway/pull/39) ([billybonks](https://github.com/billybonks))
- feat: configure [\#38](https://github.com/Hyper-Unearthing/llm_gateway/pull/38) ([billybonks](https://github.com/billybonks))
- fix: alias clients to old classname until 1.0 [\#36](https://github.com/Hyper-Unearthing/llm_gateway/pull/36) ([billybonks](https://github.com/billybonks))
- refactor: adapter to split clients from adapter [\#35](https://github.com/Hyper-Unearthing/llm_gateway/pull/35) ([billybonks](https://github.com/billybonks))
- test: make tests less brittle when regenerating vcr [\#34](https://github.com/Hyper-Unearthing/llm_gateway/pull/34) ([billybonks](https://github.com/billybonks))
- Clean up gems and delete sample code [\#33](https://github.com/Hyper-Unearthing/llm_gateway/pull/33) ([billybonks](https://github.com/billybonks))
- feat: add clade subscription as a seperate provider [\#32](https://github.com/Hyper-Unearthing/llm_gateway/pull/32) ([billybonks](https://github.com/billybonks))

## [v0.3.0](https://github.com/Hyper-Unearthing/llm_gateway/tree/v0.3.0) (2025-08-19)

[Full Changelog](https://github.com/Hyper-Unearthing/llm_gateway/compare/v0.2.0...v0.3.0)

**Merged pull requests:**

- feat: create a method called responses to implement modern apis [\#30](https://github.com/Hyper-Unearthing/llm_gateway/pull/30) ([billybonks](https://github.com/billybonks))
- test: Create a test that asserts the transcript format. [\#29](https://github.com/Hyper-Unearthing/llm_gateway/pull/29) ([billybonks](https://github.com/billybonks))
- refactor: move open ai chat completions to its own folder [\#28](https://github.com/Hyper-Unearthing/llm_gateway/pull/28) ([billybonks](https://github.com/billybonks))
- refactor: bundle all provider resources in a hash [\#27](https://github.com/Hyper-Unearthing/llm_gateway/pull/27) ([billybonks](https://github.com/billybonks))
- refactor: message mapper to become bidirectional mapper [\#26](https://github.com/Hyper-Unearthing/llm_gateway/pull/26) ([billybonks](https://github.com/billybonks))
- refactor: extract message mapper from input mapper [\#25](https://github.com/Hyper-Unearthing/llm_gateway/pull/25) ([billybonks](https://github.com/billybonks))
- docs: add more information about how the library works [\#24](https://github.com/Hyper-Unearthing/llm_gateway/pull/24) ([billybonks](https://github.com/billybonks))
- feat: enable uploading and downloading files from openai anthropic [\#23](https://github.com/Hyper-Unearthing/llm_gateway/pull/23) ([billybonks](https://github.com/billybonks))
- ci: upload build version to github when we release [\#22](https://github.com/Hyper-Unearthing/llm_gateway/pull/22) ([billybonks](https://github.com/billybonks))

## [v0.2.0](https://github.com/Hyper-Unearthing/llm_gateway/tree/v0.2.0) (2025-08-08)

[Full Changelog](https://github.com/Hyper-Unearthing/llm_gateway/compare/v0.1.6...v0.2.0)

**Merged pull requests:**

- feat: improve read me  [\#21](https://github.com/Hyper-Unearthing/llm_gateway/pull/21) ([billybonks](https://github.com/billybonks))
- refactor: remove fluent mapper from the lib [\#20](https://github.com/Hyper-Unearthing/llm_gateway/pull/20) ([billybonks](https://github.com/billybonks))
- test: dont fail vcr if key order changes [\#19](https://github.com/Hyper-Unearthing/llm_gateway/pull/19) ([billybonks](https://github.com/billybonks))
- burn: fluent mapper from input mappers [\#18](https://github.com/Hyper-Unearthing/llm_gateway/pull/18) ([billybonks](https://github.com/billybonks))
- test: open ai mapper [\#17](https://github.com/Hyper-Unearthing/llm_gateway/pull/17) ([billybonks](https://github.com/billybonks))
- feat: handle basic text document handling [\#16](https://github.com/Hyper-Unearthing/llm_gateway/pull/16) ([billybonks](https://github.com/billybonks))
- test: improve issues [\#15](https://github.com/Hyper-Unearthing/llm_gateway/pull/15) ([billybonks](https://github.com/billybonks))
- style: format aligment of content automatically to my preference [\#14](https://github.com/Hyper-Unearthing/llm_gateway/pull/14) ([billybonks](https://github.com/billybonks))
- fix: tool calling open ai [\#13](https://github.com/Hyper-Unearthing/llm_gateway/pull/13) ([billybonks](https://github.com/billybonks))

## [v0.1.6](https://github.com/Hyper-Unearthing/llm_gateway/tree/v0.1.6) (2025-08-05)

[Full Changelog](https://github.com/Hyper-Unearthing/llm_gateway/compare/v0.1.5...v0.1.6)

**Merged pull requests:**

- Fix gem release task commit message interpolation [\#12](https://github.com/Hyper-Unearthing/llm_gateway/pull/12) ([billybonks](https://github.com/billybonks))

## [v0.1.5](https://github.com/Hyper-Unearthing/llm_gateway/tree/v0.1.5) (2025-08-05)

[Full Changelog](https://github.com/Hyper-Unearthing/llm_gateway/compare/v0.1.4...v0.1.5)

**Merged pull requests:**

- burn: login from tool base class [\#11](https://github.com/Hyper-Unearthing/llm_gateway/pull/11) ([billybonks](https://github.com/billybonks))
- improve sample [\#10](https://github.com/Hyper-Unearthing/llm_gateway/pull/10) ([billybonks](https://github.com/billybonks))
- ci: mark latest change log as a version [\#9](https://github.com/Hyper-Unearthing/llm_gateway/pull/9) ([billybonks](https://github.com/billybonks))
- ci: improve rake release task, so i get burnt less [\#8](https://github.com/Hyper-Unearthing/llm_gateway/pull/8) ([billybonks](https://github.com/billybonks))

## [v0.1.4](https://github.com/Hyper-Unearthing/llm_gateway/tree/v0.1.4) (2025-08-04)

[Full Changelog](https://github.com/Hyper-Unearthing/llm_gateway/compare/v0.1.3...v0.1.4)

**Merged pull requests:**

- ci: release should ask me what version i want to bump [\#7](https://github.com/Hyper-Unearthing/llm_gateway/pull/7) ([billybonks](https://github.com/billybonks))
- docs: create an real world example that does something interesting [\#6](https://github.com/Hyper-Unearthing/llm_gateway/pull/6) ([billybonks](https://github.com/billybonks))
- feat: there was no way to pass api\_key to gateway besides env [\#5](https://github.com/Hyper-Unearthing/llm_gateway/pull/5) ([billybonks](https://github.com/billybonks))

## [v0.1.3](https://github.com/Hyper-Unearthing/llm_gateway/tree/v0.1.3) (2025-08-04)

[Full Changelog](https://github.com/Hyper-Unearthing/llm_gateway/compare/v0.1.2...v0.1.3)

**Merged pull requests:**

- feat: add tool base class [\#4](https://github.com/Hyper-Unearthing/llm_gateway/pull/4) ([billybonks](https://github.com/billybonks))

## [v0.1.2](https://github.com/Hyper-Unearthing/llm_gateway/tree/v0.1.2) (2025-08-04)

[Full Changelog](https://github.com/Hyper-Unearthing/llm_gateway/compare/v0.1.1...v0.1.2)

**Merged pull requests:**

- feat: add prompt base class [\#3](https://github.com/Hyper-Unearthing/llm_gateway/pull/3) ([billybonks](https://github.com/billybonks))
- lint files and add coverage [\#2](https://github.com/Hyper-Unearthing/llm_gateway/pull/2) ([billybonks](https://github.com/billybonks))
- test: vcr lookup was not working when using different commands [\#1](https://github.com/Hyper-Unearthing/llm_gateway/pull/1) ([billybonks](https://github.com/billybonks))

## [v0.1.1](https://github.com/Hyper-Unearthing/llm_gateway/tree/v0.1.1) (2025-08-04)

[Full Changelog](https://github.com/Hyper-Unearthing/llm_gateway/compare/v0.1.0...v0.1.1)

## [v0.1.0](https://github.com/Hyper-Unearthing/llm_gateway/tree/v0.1.0) (2025-08-04)

[Full Changelog](https://github.com/Hyper-Unearthing/llm_gateway/compare/505c78116a2e778b23f319a380cd4bf6e300db89...v0.1.0)



\* *This Changelog was automatically generated by [github_changelog_generator](https://github.com/github-changelog-generator/github-changelog-generator)*
