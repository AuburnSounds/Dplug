# Contributing to Dplug

First off, thanks for taking the time to contribute.

The following is a set of guidelines for contributing to Dplug and its packages, which are hosted in the [Auburn Sounds Organization](https://github.com/AuburnSounds/) on GitHub.

Use your best judgment, and feel free to propose changes to this document in a pull request.


## 1. If possible, discuss changes ahead of time with the maintainer

Please open new bugs in the bugtracker before doing a PR.
This tends to lead to a better outcome.


## 2. Follow existing style

Dplug uses the Phobos D style: https://dlang.org/dstyle.html
That means no TABs and 4 spaces of indentation.

Additionally Dplug uses a "runtime-free" D which entails no GC allocation. Most of knowledge and functions related to it is located in `dplug:core`.

Tools and plugin host are not limited to be runtime-free though.


## 3. Don't complicate the build

Dplug should keep being be a *small* 2mb archive downloaded by DUB from time to time, and nothing more.

**Being able to update Dplug over slow network is a feature of the library, this allow to develop while being nomad.**

Don't add new languages, libraries or constraints without discussion.


## 4. Documented decisions

Always add `TODO` comments for _any_ doubt your may have. Don't sweep subtle decisions or race conditions under the rug.


## 5. Breaking changes

Breaking changes are allowed for now.
When renaming, introduce a `deprecated("Use this symbol instead: foo") alias bar = foo;` line.
