
# Important notes on reporting Issues

- **State clearly what your problem is.**

- **Give us a way to reproduce a problem.** If you don't do this, **it might never get fixed.**

- **Have no expectation.** Dplug is there to support existing companies and products first. Because there is no money in bugfixing for people on the Internet, the alloted time for that is effectively zero. **You are basically on your own, and noone owes you a bug fix.**


# Contributing to Dplug

First off, thanks for taking the time to contribute.

The following is a set of guidelines for contributing to Dplug and its packages, which are hosted in the [Auburn Sounds Organization](https://github.com/AuburnSounds/) on GitHub.

Use your best judgment, and feel free to propose changes to this document in a pull request.

## 0. Boost license

By contributing to Dplug, you implicitly agree that your work will be redistributed under the Boost license.
You still keep your copyright over the files you have modified.

When you modify a file, do not forget to **add a Copyright DDoc entry with the copyright holder name and year.**


## 1. Come discuss changes first

Please open new bugs in the bugtracker before doing a PR.
This tends to lead to a better outcome.

An even better solution is Dplug's Discord channel.


## 2. Follow existing style

Dplug uses the Phobos D style: https://dlang.org/dstyle.html
In particular that means no TABs and 4 spaces of indentation.

Additionally Dplug uses a "runtime-free" D which entails additional constraints:
https://github.com/AuburnSounds/Dplug/wiki/Working-in-a-@nogc-environment

Tools, plug-in host implementation, and unittests not restricted to be runtime-free though.


## 3. Don't complicate the build

Dplug should keep being be a *small* archive downloaded by DUB from time to time, and nothing more.

**Being able to update Dplug over slow network is a feature of the library, this allow to develop while being nomad.**

Don't add new languages, libraries or constraints without discussion.


## 4. Documented decisions

Always add `TODO` comments for _any_ doubt your may have. Don't sweep subtle decisions or race conditions under the rug.


## 5. Breaking changes

Breaking changes are not allowed unless there is discussion first.
When just renaming, introduce a `deprecated("Use this symbol instead: foo") alias bar = foo;` line.


## 6. Important Design rules

- Dplug's window backend should have the same functionality.

- Dplug's plugin clients should have the same functionality.

- Dplug should work the latest D compilers and the largest possible extent of past compilers that fits the need of plug-in development

- In Dplug all plug-in parameters are considered automatable. This could change in the future but this is the current state right now.

- Dplug supports dynamic latency changes, however a plug-in's latency can only depends on the samplerate only, not on a parameter change.
