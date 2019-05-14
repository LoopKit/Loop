set -x
set -u
set -e

# Uncomment if you have not already cloned the repo:
# git clone https://github.com/ps2/loop-priv.git
# cd loop-priv

git checkout omnipod-testing

carthage bootstrap --use-submodules --no-build

git reset HEAD

cd Carthage/Checkouts
cd LoopKit; git fetch; git checkout omnipod-testing; git pull; cd ..
cd rileylink_ios; git fetch; git checkout omnipod-testing; git pull; cd ..
cd CGMBLEKit; git fetch; git checkout omnipod-testing; git pull; cd ..
cd dexcom-share-client-swift; git fetch; git checkout omnipod-testing; git pull; cd ..
cd G4ShareSpy; git fetch; git checkout omnipod-testing; git pull; cd ..
cd ../..
carthage build

echo "Open Xcode, and select File -> New -> Workspace and create "Loop.xcworkspace" in the loop-priv directory just created.
Select File -> Add Files to "Loop"... to add the Loop.xcodeproj project.
Repeatedly select File -> Add Files to "Loop"... to add the .xcodeproj file for each project within the Carthage/Checkouts directory.
run 'carthage build' at the top level Loop directory
Build Loop in Xcode!"
