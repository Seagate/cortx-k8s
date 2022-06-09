<!--
Thank you for your contribution! Before opening this pull request, please complete the template
completely. Unless instructed otherwise, do not delete any sections.
-->
## Description
<!--
Describe what this change does and the motivation behind it. Why is it required? What problems does
it solve?
-->

## Breaking change
<!--
If this change introduces any breaking changes, describe what it breaks and what action is required
to address it. We prefer deprecating things first before breaking them entirely. If you are unable
to support deprecation in this change, or are actually removing the deprecated the item, please
state so.

You can delete this section if there are no breaking changes.
-->

## Type of change
<!--
What type of change is this? Does it fix an issue, or is it new functionality? Check as many items
as necessary to accurately describe the change. If you are checking more than one of the items,
consider splitting it up into separate PRs if it makes sense.
-->
- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds new functionality)
- [ ] Breaking change (bug fix or new feature that breaks existing functionality)
- [ ] Third-party dependency update
- [ ] Documentation additions or improvements
- [ ] Code quality improvements to existing code or test additions/updates

## Applicable issues
<!--
If this change directly fixes or is related to any existing GitHub or Jira issue, mention those
here. You can reference a GitHub issue using "#<issue number>". If this is related to a Seagate
internal issue (Jira), please reference the CORTX-NNNNN issue number.
-->
- This change fixes an issue: #
- This change is related to an issue: #

## CORTX image version requirements
<!--
If this change requires specific versions of CORTX that are newer than the currently referenced
images, please list those images and link them to the public CORTX packages page.

- cortx-data images are published at https://github.com/Seagate/cortx/pkgs/container/cortx-data
- cortx-rgw images are published at https://github.com/Seagate/cortx/pkgs/container/cortx-rgw
- cortx-control images are published at https://github.com/Seagate/cortx/pkgs/container/cortx-control

The referenced images are always defined in the images section of the solution.example.yaml file. If
updated images are required, the example solution YAML file should be updated in this change. The Helm chart `appVersion` field must also be updated to match the version of the images.

If the currently referenced CORTX container images support this change, you can delete this section
or indicate that.

*NOTE* that we cannot merge any PRs that depend on non-public images!
-->
This change requires the following images:

- `cortx-data:<version>`
- `cortx-rgw:<version>`
- `cortx-control:<version>`

## How was this tested?
<!--
In-lieu of requiring automated tests for changes (we're working on that!), we are asking you to
provide a brief description of how this change was tested, especially any details specific to the
change.
-->

## Additional information
<!--
Feel free to mention any other information here about this PR that you feel is important and doesn't
fit into any of the other sections.
-->

## Checklist
<!--
Place an 'x' in all the items that apply. You can also fill them out after the PR is submitted. This
serves as a reminder for what the maintainers will be looking for when reviewing the change.
-->

- [ ] The change is tested and works locally.
- [ ] New or changed settings in the solution YAML are documented clearly in the README.md file.
- [ ] All commits are signed off and are in agreement with the [CORTX Community DCO and CLA policy](https://github.com/Seagate/cortx/blob/main/doc/dco_cla.md).

If this change requires newer CORTX or third party image versions:

- [ ] The `image` fields in [solution.example.yaml](../k8_cortx_cloud/solution.example.yaml) have been updated to use the required versions.
- [ ] The `appVersion` field of the [Helm chart](../charts/cortx/Chart.yaml) has been updated to use the new CORTX version.

If this change addresses a CORTX Jira issue:

- [ ] The title of the PR starts with the issue ID (e.g. `CORTX-XXXXX:`)
