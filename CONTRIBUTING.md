# Contributing to Dplug

First off, thanks for taking the time to contribute.

The following is a set of guidelines for contributing to Dplug and its packages, which are hosted in the [Auburn Sounds Organization](https://github.com/AuburnSounds/) on GitHub.

Use your best judgment, and feel free to propose changes to this document in a pull request.

## 0. Boost license

By contributing to Dplug, you implicitely agree that your work will be redistributed under the Boost license.
You still keep your copyright over the files you have modified.

When you modify a file, do not forget to add a Copyright DDoc entry with the copyright holder name and year.
For a significant contribution, do not forget to add youself to the "author" field in `dub.json`.

## 1. Come discuss changes first

Please open new bugs in the bugtracker before doing a PR.
This tends to lead to a better outcome.

An even better solution is Dplug's Discord channel.


## 2. Follow existing style

Dplug uses the Phobos D style: https://dlang.org/dstyle.html
In particular that means no TABs and 4 spaces of indentation.

Additionally Dplug uses a "runtime-free" D which entails additional constraints:


Tools, plugin host implementation, and unittests not restricted to be runtime-free though.


## 3. Don't complicate the build

Dplug should keep being be a *small* 2mb archive downloaded by DUB from time to time, and nothing more.

**Being able to update Dplug over slow network is a feature of the library, this allow to develop while being nomad.**

Don't add new languages, libraries or constraints without discussion.


## 4. Documented decisions

Always add `TODO` comments for _any_ doubt your may have. Don't sweep subtle decisions or race conditions under the rug.


## 5. Breaking changes

Breaking changes are allowed for now.
When renaming, introduce a `deprecated("Use this symbol instead: foo") alias bar = foo;` line.
