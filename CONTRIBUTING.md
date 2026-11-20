# Contributing

## What is welcome

- Bugs, with the device, the engine, the level and the moves played. The game log's PGN export has all of it.
- Engine ports. Another engine needs a program and a network that both carry a clear license, a build script that fetches a pinned source, and a pack that passes `engines/check.mjs` and `engines/check-webkit.mjs`. Read [`engines/README.md`](engines/README.md) and copy the shape of an existing folder.
- Fixes to the apps and to `core/`, small and with a test where there is logic.

## What is not taken

- Changes to `engines/zeist/` and to the Zeist rules. They are copied one way from Zeist's own repository so that Zeist can keep using them. Report problems as issues; they are fixed at the source.
- Chat, social features, ads, or anything that nags. Zeist Chess is for practice, and you play engines, not people.
- Engines or data without a clear license, however strong the engine.

## How things are done here

- Copy is plain American English. No em-dashes, no slogans, never the word "new".
- The look is Zeist's: graphite and bone, Prata for titles, Jost for text, pill buttons, ivory and ebony pieces.
- The web and `core/` have no build step for app code.
- A design change comes with screenshots.
- Product decisions are one person's taste; a change that goes against how the app works today needs a reason.

## License of contributions

By contributing you agree that your work is licensed under the AGPL-3.0-or-later, like the rest of the app. That includes the additional permission in [`LICENSE-EXCEPTION.md`](LICENSE-EXCEPTION.md). Engine folders keep the license of their engine.

Lessons are the one exception to how contributions are used. The lessons here are also used by Zeist, which is closed source, under a separate license from their copyright holder ([`LICENSE-LESSONS.md`](LICENSE-LESSONS.md)). A contribution to the lessons is taken under the AGPL only, like any other, and does not pass to Zeist unless you say in writing that it may. For that reason changes to lesson text and positions are best reported as issues: a fix written by the maintainer can reach both.
