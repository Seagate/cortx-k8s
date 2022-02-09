# Contribute to the CORTX Project

CORTX is about building the world's best scalable mass-capacity object storage system. If you’re interested in what we’re building and intrigued by hard challenges, here's everything you need to know about contributing to the project and how to get started. 

This guide is intended to provide quick start instructions for developers who want to build, test, and contribute to the CORTX software running on Kubernetes.

After reading this guide, you'll be able to pick up topics and issues to contribute, submit your code, and how to turn your pull request into a successful contribution. And if you have any suggestions on how we can improve this guide, or anything else in the project, we want to hear from you!

## Code of Conduct

Thanks for joining us and we're glad to have you. We take community very seriously and we are committed to creating a community built on respectful interactions and inclusivity as documented in our [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md). 

You can report instances of abusive, harassing, or otherwise unacceptable behavior by contacting the project team at opensource@seagate.com.

## Deployment and Testing
- Learn various methods to acquire, build, run and test CORTX on Kubernetes in the [Quick Start Guides](https://github.com/Seagate/cortx-k8s#quick-starts) section of our [README](README.md).

## Repository Overview

### Branches

- `main`: The primary branch for the repository. This branch will be the source for all `cortx-k8s` releases and is managed only by the [Maintainers](#maintainers) of the repository.
- `integration`: This branch does the bulk of the heavy lifting for the `cortx-k8s` project, as it is the target for all Pull Requests - both internal to the repository and external from forked repositories. Maintainers of the repository merge from `integration` to `main` to control the release flow of the repository.
- `cortx-test`: An internal development-focused branch to stage breaking changes, while allowing the larger community to test CORTX in motion.
- `CORTX-12345...`: Branches with the format of `CORTX-12345` are feature branches that are actively being worked upon by contributors and will eventually be PR'ed into `integration` once complete. Due to historical changes in tooling, feature branches may also begin with `EOS` or `UDX` as well. 

## Contribution Process

### Prerequisites

The following prerequisites are all available in the root [CORTX](https://github.com/Seagate/cortx) repository:

- Please read the [CORTX Code Style Guide](https://github.com/Seagate/cortx/blob/main/doc/CodeStyle.md).
- Get started with [GitHub Tools and Procedures](https://github.com/Seagate/cortx/blob/main/doc/GitHub_Processes_and_Tools.rst), if you are new to GitHub.
   - Please find additional information about [working with git](https://github.com/Seagate/cortx/blob/main/doc/working_with_git.md) specific to CORTX.
- Please read about our [DCO and CLA policies](https://github.com/Seagate/cortx/blob/main/doc/dco_cla.md) in the root [CORTX](https://github.com/Seagate/cortx) repository.

### Submitting a PR

This compact flow for submitting a Pull Request to the [cortx-k8s](https://github.com/Seagate/cortx-k8s) repository will help ensure that it is able to be accepted and merged with minimal overhead or editing. 

> :warning: The target branch of your Pull Request should be **`integration`** (as documented below).

1. Fork [this repository](https://github.com/Seagate/cortx-k8s) to another personal or organization account on GitHub.
2. Create a new development branch off of the upstream (also known as the original repository's) `integration` branch.
   - `git checkout -b <my-new-feature-branch> integration`
3. Do your work, including writing code, writing tests, updating documentation, and passing all tests locally.
4. Fetch the latest upstream changes to ensure you have the latest working copy of the upstream codebase.
   - `git fetch upstream`
5. Rebase your changes on top of the latest upstream streams, being sure to resolve any conflicts. _(This process allows you to resolve any local issues with your changes, one by one, before submitting your PR instead of afterwards.)_
   - `git branch --set-upstream-to=upstream/integration`
   - `git rebase`
6. Push your rebased change set to your repository.
   - `git push origin <my-new-feature-branch>`
7. Create a pull request from your `<my-new-feature-branch>` against the upstream **`integration`** branch.
   1. _**NOTE:**_ The target branch of your Pull Request should be `integration`, not `main`!
   2. Either in the initial comment section of your Pull Request or in the **Reviewers** section, you will need to tag **@cortx-k8s-admins** for the project maintainers to be made aware of your pull request.
   - _Reference:_ [Creating a pull request](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/creating-a-pull-request)
8. Your PR will be reviewed, inspected, and (if appropriate) automatically tested using integrated CI/CD workflows. Once complete, project maintainers will accept the PR and merge the code changes into the `integration` branch.
9. Congratulations! You have now successfully contributed to making the CORTX project even better!

## Additional Resources

- Learn more about the [CORTX Architechture](https://github.com/Seagate/cortx/blob/main/doc/architecture.md). 
- Learn more about [CORTX CI/CD and Automation](https://github.com/Seagate/cortx/blob/main/doc/CI_CD.md).
- Browse our [suggested list of contributions](https://github.com/Seagate/cortx/blob/main/doc/SuggestedContributions.md).

## Communication Channels

Please refer to the [Support](https://github.com/Seagate/cortx/blob/main/SUPPORT.md) section in the root [CORTX](https://github.com/Seagate/cortx) repository to learn more about the various channels by which you can reach out to us. 

## Maintainers

Active and past maintainers of the [cortx-k8s](https://github.com/Seagate/cortx-k8s) project are tracked via the [MAINTAINERS.md](MAINTAINERS.md) page. Please use this page for further discussion, communication, and questions as needed while working with CORTX on Kubernetes.

## Acknowledgements

After making a contribution, please don't forget to include yourself in our [Contributors list](https://github.com/Seagate/cortx/blob/main/CONTRIBUTORS.md) in the root [CORTX](https://github.com/Seagate/cortx) repository!

## Thank You!

We thank you for stopping by to check out the CORTX Community. We are fully dedicated to our mission to build open source technologies that help the world save unlimited data and solve challenging data problems. Join our mission to help reinvent a data-driven world.