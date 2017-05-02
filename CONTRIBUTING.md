# Contributing to Dplug

First off, thanks for taking the time to contribute.

The following is a set of guidelines for contributing to Dplug and its packages, which are hosted in the [Auburn Sounds Organization](https://github.com/aubursounds) on GitHub.

Use your best judgment, and feel free to propose changes to this document in a pull request.


## Discuss change before with the maintainer

Please open new bugs in the bugtracker before doing a PR.
This always lead to a better outcome.


## Follow the existing style

Dplug uses the Phobos D style: https://dlang.org/dstyle.html
That means no TABs and 4 spaces of indentation.


## Don't complicate the build

Dplug should keep being be a *small* 2mb archive downloaded by DUB from time to time, and nothing more.

**Being able to update Dplug over slow network is a feature of the library.**

Don't add new languages, libraries or constraints


## Don't sweep it under the rug

Always add TODO comments for _any_ doubt your may have. Don't sweep subtle decisions or race conditions under the rug.

