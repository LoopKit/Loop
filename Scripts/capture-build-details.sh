#!/bin/sh -e

#  capture-build-details.sh
#  Loop
#
#  Copyright © 2019 LoopKit Authors. All rights reserved.

SCRIPT="$(basename "${0}")"
SCRIPT_DIRECTORY="$(dirname "${0}")"

error() {
  echo "ERROR: ${*}" >&2
  echo "Usage: ${SCRIPT} [-r|--git-source-root git-source-root] [-p|--provisioning-profile-path provisioning-profile-path]" >&2
  echo "Parameters:" >&2
  echo "  -p|--provisioning-profile-path <provisioning-profile-path> path to the .mobileprovision provisioning profile file to check for expiration; optional, defaults to \${HOME}/Library/MobileDevice/Provisioning Profiles/\${EXPANDED_PROVISIONING_PROFILE}.mobileprovision" >&2
  exit 1
}

warn() {
  echo "WARN: ${*}" >&2
}

info() {
  echo "INFO: ${*}" >&2
}

info_plist_path="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/BuildDetails.plist"
xcode_build_version=${XCODE_PRODUCT_BUILD_VERSION:-$(xcodebuild -version | grep version | cut -d ' ' -f 3)}

while [[ $# -gt 0 ]]
do
  case $1 in
    -i|--info-plist-path)
      info_plist_path="${2}"
      shift 2
      ;;
    -p|--provisioning-profile-path)
      provisioning_profile_path="${2}"
      shift 2
      ;;
  esac
done

if [ ${#} -ne 0 ]; then
  error "Unexpected arguments: ${*}"
fi

if [ "${info_plist_path}" == "/" -o ! -e "${info_plist_path}" ]; then
  error "File does not exist: ${info_plist_path}"
fi

info "Gathering build details in ${PWD}"

if [ -e .git ]; then
  rev=$(git rev-parse HEAD)
  plutil -replace com-loopkit-Loop-git-revision -string ${rev:0:7} "${info_plist_path}"
  branch=$(git branch --show-current)
  if [ -n "$branch" ]; then
    plutil -replace com-loopkit-Loop-git-branch -string "${branch}" "${info_plist_path}"
  else
    warn "No git branch found, not setting com-loopkit-Loop-git-branch"
  fi
fi

plutil -replace com-loopkit-Loop-srcroot -string "${PWD}" "${info_plist_path}"
plutil -replace com-loopkit-Loop-build-date -string "$(date)" "${info_plist_path}"
plutil -replace com-loopkit-Loop-xcode-version -string "${xcode_build_version}" "${info_plist_path}"

# Determine the provisioning profile path
if [ -z "${provisioning_profile_path}" ]; then
  if [ -e "${HOME}/Library/MobileDevice/Provisioning Profiles/${EXPANDED_PROVISIONING_PROFILE}.mobileprovision" ]; then
    provisioning_profile_path="${HOME}/Library/MobileDevice/Provisioning Profiles/${EXPANDED_PROVISIONING_PROFILE}.mobileprovision"
  elif [ -e "${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles/${EXPANDED_PROVISIONING_PROFILE}.mobileprovision" ]; then
    provisioning_profile_path="${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles/${EXPANDED_PROVISIONING_PROFILE}.mobileprovision"
  else
    warn "Provisioning profile not found in expected locations"
  fi
fi

if [ -e "${provisioning_profile_path}" ]; then
  profile_expire_date=$(security cms -D -i "${provisioning_profile_path}" | plutil -p - | grep ExpirationDate | cut -b 23-)
  # Convert to plutil format
  profile_expire_date=$(date -j -f "%Y-%m-%d %H:%M:%S" "${profile_expire_date}" +"%Y-%m-%dT%H:%M:%SZ")
  plutil -replace com-loopkit-Loop-profile-expiration -date "${profile_expire_date}" "${info_plist_path}"
else
  warn "Invalid provisioning profile path ${provisioning_profile_path}"
fi

# determine if this is a workspace build
# if so, fill out the git revision and branch
if [ -e ../.git ]
then
    pushd . > /dev/null
    cd ..
    rev=$(git rev-parse HEAD)
    plutil -replace com-loopkit-LoopWorkspace-git-revision -string "${rev:0:7}" "${info_plist_path}"
    branch=$(git branch --show-current)
    if [ -n "$branch" ]; then
        plutil -replace com-loopkit-LoopWorkspace-git-branch -string "${branch}" "${info_plist_path}"
    fi
    popd . > /dev/null
fi

# --- Root repo details ---
# Retrieve current branch (or tag) and commit SHA.
git_branch=$(git symbolic-ref --short -q HEAD || echo "")
git_tag=$(git describe --tags --exact-match 2>/dev/null || echo "")
git_commit_sha=$(git log -1 --format="%h" --abbrev=7)
git_branch_or_tag="${git_branch:-${git_tag}}"
if [ -z "${git_branch_or_tag}" ]; then
    git_branch_or_tag="detached"
fi

plutil -replace com-loopkit-Loop-branch -string "${git_branch_or_tag}" "${info_plist_path}"
plutil -replace com-loopkit-Loop-commit-sha -string "${git_commit_sha}" "${info_plist_path}"

# --- Submodule details ---
# Remove an existing submodules key if it exists, then create an empty dictionary.
# (Using PlistBuddy, which is available on macOS)
submodules_key="com-loopkit-Loop-submodules"
if /usr/libexec/PlistBuddy -c "Print :${submodules_key}" "${info_plist_path}" 2>/dev/null; then
    /usr/libexec/PlistBuddy -c "Delete :${submodules_key}" "${info_plist_path}"
fi
/usr/libexec/PlistBuddy -c "Add :${submodules_key} dict" "${info_plist_path}"

# Gather submodule details.
# We use git submodule foreach to output lines in the form:
#   submodule_name|branch_or_tag|commit_sha
submodules_info=$(git submodule foreach --quiet '
  sub_git_branch=$(git symbolic-ref --short -q HEAD || echo "")
  sub_git_tag=$(git describe --tags --exact-match 2>/dev/null || echo "")
  sub_git_commit_sha=$(git log -1 --format="%h" --abbrev=7)
  sub_git_branch_or_tag="${sub_git_branch:-${sub_git_tag}}"
  if [ -z "${sub_git_branch_or_tag}" ]; then
    sub_git_branch_or_tag="detached"
  fi
  echo "$name|$sub_git_branch_or_tag|$sub_git_commit_sha"
')

# For each line, add a dictionary entry for that submodule.
echo "${submodules_info}" | while IFS="|" read -r submodule_name sub_branch sub_sha; do
    # Create a dictionary for this submodule
    /usr/libexec/PlistBuddy -c "Add :${submodules_key}:${submodule_name} dict" "${info_plist_path}"
    /usr/libexec/PlistBuddy -c "Add :${submodules_key}:${submodule_name}:branch string ${sub_branch}" "${info_plist_path}"
    /usr/libexec/PlistBuddy -c "Add :${submodules_key}:${submodule_name}:commit_sha string ${sub_sha}" "${info_plist_path}"
done

echo "BuildDetails.plist has been updated at: ${info_plist_path}"