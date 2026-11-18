# Additional permission for analytics libraries

Zeist Chess is licensed under the GNU Affero General Public License, version 3 or later (see `LICENSE`).

The iPhone app measures usage with Google Analytics. Part of Google's library for this is distributed only in
compiled form. So that the app can be built and shared with it, the copyright holder grants the following.

**Additional permission under GNU AGPL version 3 section 7.** If you modify this Program, or any covered work, by
linking or combining it with Google's Firebase Analytics libraries for iOS (FirebaseAnalytics, GoogleAppMeasurement
and the libraries they depend on), or a modified version of those libraries, the copyright holder of Zeist Chess
grants you additional permission to convey the resulting work. Corresponding Source for a non-source form of such a
combination shall include the source code for the parts of those libraries that are available as source, as well as
that of the covered work.

## What this covers

- The code written for Zeist Chess: `core/` (except `core/vendor/`), `ios/`, `web/`, `scripts/`, the build scripts
  and glue under `engines/`, and the Zeist engine.
- It does not change the license of anything by other authors: the engines, their networks, the piece sets,
  chess.js, the fonts. The engines are separate programs that the app talks to in plain text (UCI); they are not
  linked with the analytics library.

## Building without it

A build without `GoogleService-Info.plist` (which is not in this repository) measures nothing. In the app, the
switch is in Settings under Privacy. What is sent is listed in `ios/ZeistChess/App/Measure.swift`.
